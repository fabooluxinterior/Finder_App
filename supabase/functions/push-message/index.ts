// Called by the database after a message is stored: POST { message_id } with header x-push-secret.
// Sends "<name>: Sent you a message" to the receiver's registered phones so it appears in the
// notification bar when the app is closed. Never includes message content (it is encrypted).
import { admin } from "../_shared/auth.ts";
import { fcmAccessToken, parseServiceAccount, sendFcm } from "../_shared/fcm.ts";
import { handle, HttpError, json } from "../_shared/http.ts";
import { isUuid, messageNotice, secretMatches } from "../_shared/push_message.ts";

Deno.serve((req) =>
  handle(req, async () => {
    if (req.method !== "POST") throw new HttpError(405, "method", "POST only.");
    if (!secretMatches(req.headers.get("x-push-secret"), Deno.env.get("PUSH_WEBHOOK_SECRET"))) {
      throw new HttpError(401, "unauthenticated", "Not allowed.");
    }
    const b = await req.json().catch(() => ({}));
    if (!isUuid(b.message_id)) throw new HttpError(400, "bad_request", "message_id required.");

    const sa = parseServiceAccount(Deno.env.get("FCM_SERVICE_ACCOUNT"));
    if (!sa) return json(req, { sent: 0, push_configured: false });

    const { data: m } = await admin.from("messages").select("sender_id, receiver_id").eq("id", b.message_id).maybeSingle();
    if (!m) return json(req, { sent: 0 });
    const [{ data: sender }, { data: devices }] = await Promise.all([
      admin.from("profiles").select("full_name").eq("id", m.sender_id).maybeSingle(),
      admin.from("push_devices").select("token").eq("user_id", m.receiver_id).limit(5),
    ]);
    const tokens = (devices ?? []).map((d: { token: string }) => d.token);
    if (tokens.length === 0) return json(req, { sent: 0 });

    const { title, body } = messageNotice(sender?.full_name);
    const accessToken = await fcmAccessToken(sa);
    const dead: string[] = [];
    let sent = 0;
    await Promise.all(tokens.map(async (t: string) => {
      const r = await sendFcm(sa, accessToken, t, title, body, { kind: "message", tag: `chat-${m.sender_id}` }).catch(() => "failed" as const);
      if (r === "ok") sent++;
      else if (r === "unregistered") dead.push(t);
    }));
    if (dead.length) await admin.from("push_devices").delete().in("token", dead);
    return json(req, { sent });
  }));
