// Supabase "Send SMS" auth hook: texts the sign-in code through MSG91.
//
// Called by Supabase Auth with a Standard Webhooks signature, not a user JWT,
// so verify_jwt is off (see supabase/config.toml) and the signature is the
// authentication: nobody else can make this function send a text.
// Server-only secrets: SEND_SMS_HOOK_SECRET, MSG91_AUTHKEY, MSG91_TEMPLATE_ID.
import { indianMobile, maskNumber, sendMsg91Otp, type SmsHookPayload, verifyHookSignature } from "../_shared/sms_hook.ts";

const reply = (status: number, message?: string) =>
  new Response(JSON.stringify(message ? { error: { http_code: status, message } } : {}), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

Deno.serve(async (req) => {
  if (req.method !== "POST") return reply(405, "Method not allowed");
  const body = await req.text();
  if (!(await verifyHookSignature(body, req.headers, Deno.env.get("SEND_SMS_HOOK_SECRET") ?? ""))) {
    return reply(401, "Invalid signature");
  }

  let payload: SmsHookPayload;
  try {
    payload = JSON.parse(body);
  } catch (_) {
    return reply(400, "Bad request");
  }
  const mobile = indianMobile(payload.user?.phone);
  const otp = payload.sms?.otp ?? "";
  if (!mobile) {
    console.log(JSON.stringify({ hook: "send-sms", result: "refused_non_indian_number" }));
    return reply(400, "Only Indian mobile numbers are supported.");
  }

  const result = await sendMsg91Otp(mobile, otp, (k) => Deno.env.get(k));
  console.log(JSON.stringify({ hook: "send-sms", to: maskNumber(mobile), result }));
  if (result === "sent") return reply(200);
  return reply(
    500,
    result === "not_configured" ? "SMS sender is not configured." : "Couldn't send the code. Try again in a minute.",
  );
});
