// Called by the database: POST { message_id } (a new chat message) or { notification_id } (a row in the
// user's notification list: request, connection, suggestions, moderation, ticket, trial) with header
// x-push-secret. Sends it to the receiver's registered phones so it appears in the notification bar.
// Chat messages show only the sender's first name: their content is encrypted and never seen here.
import { admin } from "../_shared/auth.ts";
import { diagnoseServiceAccount, fcmAccessToken, parseServiceAccount, sendFcm } from "../_shared/fcm.ts";
import { handle, HttpError, json } from "../_shared/http.ts";
import { isUuid, messageNotice, secretMatches } from "../_shared/push_message.ts";

Deno.serve((req) =>
  handle(req, async () => {
    if (req.method !== "POST") throw new HttpError(405, "method", "POST only.");
    if (!secretMatches(req.headers.get("x-push-secret"), Deno.env.get("PUSH_WEBHOOK_SECRET"))) {
      throw new HttpError(401, "unauthenticated", "Not allowed.");
    }
    const b = await req.json().catch(() => ({}));
    const sa = parseServiceAccount(Deno.env.get("FCM_SERVICE_ACCOUNT"));
    if (!sa) {
      console.error("push-message:", diagnoseServiceAccount(Deno.env.get("FCM_SERVICE_ACCOUNT")));
      return json(req, { sent: 0, push_configured: false });
    }

    // Who gets what: a new chat message (name only: content is encrypted) or a row from the notification list.
    let userId: string, title: string, body: string, kind: string, tag: string;
    if (isUuid(b.message_id)) {
      const { data: m } = await admin.from("messages").select("sender_id, receiver_id").eq("id", b.message_id).maybeSingle();
      if (!m) return json(req, { sent: 0 });
      const { data: sender } = await admin.from("profiles").select("full_name").eq("id", m.sender_id).maybeSingle();
      ({ title, body } = messageNotice(sender?.full_name));
      userId = m.receiver_id; kind = "message"; tag = `chat-${m.sender_id}`;
    } else if (Number.isInteger(b.notification_id)) {
      const { data: n } = await admin.from("user_notifications").select("user_id, kind, title, body").eq("id", b.notification_id).maybeSingle();
      if (!n) return json(req, { sent: 0 });
      userId = n.user_id; title = n.title; body = n.body; kind = n.kind; tag = `${n.kind}-${b.notification_id}`;
    } else {
      throw new HttpError(400, "bad_request", "message_id or notification_id required.");
    }

    const { data: devices } = await admin.from("push_devices").select("token").eq("user_id", userId).limit(5);
    const tokens = (devices ?? []).map((d: { token: string }) => d.token);
    if (tokens.length === 0) return json(req, { sent: 0 });

    let accessToken: string;
    try {
      accessToken = await fcmAccessToken(sa);
    } catch (e) {
      console.error("push-message: could not get a Google token:", (e as Error).message);
      throw new HttpError(502, "push_unavailable", "Push service refused the credentials.");
    }
    const dead: string[] = [];
    let sent = 0;
    await Promise.all(tokens.map(async (t: string) => {
      const r = await sendFcm(sa, accessToken, t, title, body, { kind, tag }).catch(() => "failed" as const);
      if (r === "ok") sent++;
      else if (r === "unregistered") dead.push(t);
    }));
    if (dead.length) await admin.from("push_devices").delete().in("token", dead);
    return json(req, { sent });
  }));
