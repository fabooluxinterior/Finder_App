// Sign-in codes by SMS through Supabase's "Send SMS" auth hook and MSG91.
// Pure helpers (testable). The hook secret, the MSG91 key and the code never
// appear in a response, an error or a log line; only the last 4 digits of a
// number are ever logged.

export interface SmsHookPayload {
  user?: { id?: string; phone?: string };
  sms?: { otp?: string };
}

const b64 = (s: string): Uint8Array<ArrayBuffer> => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

/** Standard Webhooks signature (what Supabase auth hooks send). The secret is
 *  "v1,whsec_<base64>". Rejects stale timestamps (5 minutes). */
export async function verifyHookSignature(
  body: string,
  headers: Headers,
  secret: string,
  nowMs: number = Date.now(),
): Promise<boolean> {
  const id = headers.get("webhook-id");
  const ts = headers.get("webhook-timestamp");
  const sigs = headers.get("webhook-signature");
  if (!id || !ts || !sigs || !secret) return false;
  const t = Number(ts);
  if (!Number.isFinite(t) || Math.abs(nowMs / 1000 - t) > 300) return false;
  let keyBytes: Uint8Array<ArrayBuffer>;
  try {
    keyBytes = b64(secret.replace(/^v1,/, "").replace(/^whsec_/, ""));
  } catch (_) {
    return false;
  }
  const key = await crypto.subtle.importKey("raw", keyBytes, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${id}.${ts}.${body}`)));
  const expected = btoa(String.fromCharCode(...mac));
  let ok = false;
  for (const part of sigs.split(" ")) {
    const [ver, sig] = part.split(",");
    if (ver !== "v1" || !sig || sig.length !== expected.length) continue;
    let diff = 0;
    for (let i = 0; i < sig.length; i++) diff |= sig.charCodeAt(i) ^ expected.charCodeAt(i);
    if (diff === 0) ok = true;
  }
  return ok;
}

/** "+91 91887-74739" / "919188774739" -> "919188774739" (MSG91 wants the country
 *  code without "+"). Only Indian mobile numbers are accepted: this stops
 *  SMS-pumping abuse and surprise costs. Returns null for anything else. */
export function indianMobile(input: string | undefined): string | null {
  const d = (input ?? "").replace(/\D/g, "");
  return /^91[6-9]\d{9}$/.test(d) ? d : null;
}

export const maskNumber = (d: string) => `******${d.slice(-4)}`;

export type SendResult = "sent" | "not_configured" | "refused" | "failed";

export type Env = (name: string) => string | undefined;

/** Sends the code Supabase generated through MSG91's OTP API (template with the
 *  DLT-approved text). MSG91 can answer HTTP 200 with {"type":"error"}, so the
 *  body is checked as well. */
export async function sendMsg91Otp(
  mobile: string,
  otp: string,
  env: Env,
  f: typeof fetch = fetch,
): Promise<SendResult> {
  const key = (env("MSG91_AUTHKEY") ?? "").trim();
  const template = (env("MSG91_TEMPLATE_ID") ?? "").trim();
  if (!key || !template) return "not_configured";
  if (!/^\d{4,9}$/.test(otp)) return "refused";
  const url = new URL("https://control.msg91.com/api/v5/otp");
  url.searchParams.set("template_id", template);
  url.searchParams.set("mobile", mobile);
  url.searchParams.set("otp", otp);
  url.searchParams.set("otp_length", String(otp.length));
  url.searchParams.set("otp_expiry", "10");
  try {
    const res = await f(url, {
      method: "POST",
      headers: { authkey: key, "Content-Type": "application/json", Accept: "application/json" },
      body: "{}",
      signal: AbortSignal.timeout(10_000),
    });
    const text = await res.text();
    if (!res.ok) return "failed";
    try {
      const j = JSON.parse(text);
      if (String(j?.type ?? "").toLowerCase() === "error") return "failed";
    } catch (_) { /* non-JSON success body */ }
    return "sent";
  } catch (_) {
    return "failed";
  }
}
