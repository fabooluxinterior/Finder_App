// Admin only: POST { title, body, audience: "all"|"free"|"plan"|"user", phone? }
// The database checks admin + two-step verification, rate-limits, logs the send and adds the message to
// each recipient's in-app list (mod_push_prepare). This function then pushes it to the registered phones
// through Firebase Cloud Messaging. Without FCM_SERVICE_ACCOUNT it still delivers in-app and says so.
import { admin, requireUser } from "../_shared/auth.ts";
import { fcmAccessToken, parseServiceAccount, sendFcm } from "../_shared/fcm.ts";
import { handle, HttpError, json } from "../_shared/http.ts";

const PAGE = 500;
const PARALLEL = 20;

Deno.serve((req) =>
  handle(req, async () => {
    if (req.method !== "POST") throw new HttpError(405, "method", "POST only.");
    const { asUser } = await requireUser(req);
    const b = await req.json().catch(() => ({}));
    const { data, error } = await asUser.rpc("mod_push_prepare", {
      p_title: String(b.title ?? ""),
      p_body: String(b.body ?? ""),
      p_audience: String(b.audience ?? ""),
      p_phone: typeof b.phone === "string" ? b.phone : null,
    });
    if (error) {
      const forbidden = error.code === "42501";
      throw new HttpError(forbidden ? 403 : 400, forbidden ? "forbidden" : "bad_request", forbidden ? "Admins only (with two-step verification)." : error.message);
    }
    const row = Array.isArray(data) ? data[0] : data;
    const campaign = row.campaign_id as string;
    const recipients = Number(row.recipients ?? 0);

    const sa = parseServiceAccount(Deno.env.get("FCM_SERVICE_ACCOUNT"));
    if (!sa) {
      return json(req, { campaign, recipients, delivered: 0, failed: 0, push_configured: false });
    }
    let accessToken: string;
    try {
      accessToken = await fcmAccessToken(sa);
    } catch {
      return json(req, { campaign, recipients, delivered: 0, failed: 0, push_configured: false, error: "Firebase refused the service account." });
    }

    let delivered = 0, failed = 0, after = "";
    for (;;) {
      const { data: page, error: e } = await admin.rpc("push_campaign_tokens", { p_campaign: campaign, p_after: after, p_limit: PAGE });
      if (e) throw new HttpError(500, "server", "Could not read the audience.");
      const tokens = (page as { token: string }[]).map((r) => r.token);
      if (tokens.length === 0) break;
      const dead: string[] = [];
      for (let i = 0; i < tokens.length; i += PARALLEL) {
        const results = await Promise.all(tokens.slice(i, i + PARALLEL).map((t) => sendFcm(sa, accessToken, t, String(b.title), String(b.body)).catch(() => "failed" as const)));
        results.forEach((r, k) => {
          if (r === "ok") delivered++;
          else {
            failed++;
            if (r === "unregistered") dead.push(tokens[i + k]);
          }
        });
      }
      if (dead.length) await admin.from("push_devices").delete().in("token", dead);
      after = tokens[tokens.length - 1];
      if (tokens.length < PAGE) break;
    }
    await admin.rpc("push_campaign_finish", { p_campaign: campaign, p_delivered: delivered, p_failed: failed });
    return json(req, { campaign, recipients, delivered, failed, push_configured: true });
  }));
