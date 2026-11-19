import { assert, assertEquals } from "jsr:@std/assert@1";
import { indianMobile, maskNumber, sendMsg91Otp, verifyHookSignature } from "../sms_hook.ts";

const raw = crypto.getRandomValues(new Uint8Array(new ArrayBuffer(24)));
const secret = "v1,whsec_" + btoa(String.fromCharCode(...raw));

async function sign(body: string, id: string, ts: number) {
  const key = await crypto.subtle.importKey("raw", raw, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${id}.${ts}.${body}`)));
  return "v1," + btoa(String.fromCharCode(...mac));
}

Deno.test("sms hook: only Supabase's signed call is accepted", async () => {
  const body = '{"user":{"phone":"919188774739"},"sms":{"otp":"123456"}}';
  const ts = Math.floor(Date.now() / 1000);
  const h = (sig: string, t = ts) =>
    new Headers({ "webhook-id": "msg_1", "webhook-timestamp": String(t), "webhook-signature": sig });
  assert(await verifyHookSignature(body, h(await sign(body, "msg_1", ts)), secret));
  assert(await verifyHookSignature(body, h("v1,bogus " + (await sign(body, "msg_1", ts))), secret), "one valid of several");
  assert(
    !(await verifyHookSignature(body.replace("123456", "654321"), h(await sign(body, "msg_1", ts)), secret)),
    "body changed",
  );
  assert(!(await verifyHookSignature(body, h(await sign(body, "msg_1", ts - 3600), ts - 3600), secret)), "stale");
  assert(!(await verifyHookSignature(body, new Headers(), secret)), "no headers");
  assert(!(await verifyHookSignature(body, h(await sign(body, "msg_1", ts)), "")), "no secret configured");
});

Deno.test("sms hook: Indian mobile numbers only", () => {
  assertEquals(indianMobile("919188774739"), "919188774739");
  assertEquals(indianMobile("+91 91887-74739"), "919188774739");
  for (const bad of [undefined, "", "9188774739", "14155552671", "+4479112345678", "915188774739", "9191887747390"]) {
    assertEquals(indianMobile(bad), null, String(bad));
  }
  assertEquals(maskNumber("919188774739"), "******4739");
});

Deno.test("sms hook: the MSG91 request, and failures never leak the key or the code", async () => {
  const env = (k: string) => ({ MSG91_AUTHKEY: "secret-auth-key", MSG91_TEMPLATE_ID: "tmpl_123" } as Record<string, string>)[k];
  assertEquals(await sendMsg91Otp("919188774739", "123456", () => undefined), "not_configured");

  let url = "";
  let key = "";
  let method = "";
  const ok = async (u: string | URL | Request, init?: RequestInit) => {
    url = String(u);
    method = String(init?.method);
    key = new Headers(init?.headers).get("authkey") ?? "";
    return new Response(JSON.stringify({ type: "success", message: "ok" }), { status: 200 });
  };
  assertEquals(await sendMsg91Otp("919188774739", "123456", env, ok), "sent");
  const u = new URL(url);
  assertEquals(u.origin + u.pathname, "https://control.msg91.com/api/v5/otp");
  assertEquals(method, "POST");
  assertEquals(u.searchParams.get("template_id"), "tmpl_123");
  assertEquals(u.searchParams.get("mobile"), "919188774739");
  assertEquals(u.searchParams.get("otp"), "123456");
  assertEquals(key, "secret-auth-key");
  assert(!url.includes("secret-auth-key"), "the key goes in a header, never in the URL");

  // MSG91 reports some failures as HTTP 200 + {"type":"error"}.
  assertEquals(
    await sendMsg91Otp(
      "919188774739",
      "123456",
      env,
      async () => new Response('{"type":"error","message":"Template not found"}', { status: 200 }),
    ),
    "failed",
  );
  assertEquals(await sendMsg91Otp("919188774739", "123456", env, async () => new Response("no", { status: 401 })), "failed");
  assertEquals(
    await sendMsg91Otp("919188774739", "123456", env, async () => {
      throw new Error("offline");
    }),
    "failed",
  );
  assertEquals(await sendMsg91Otp("919188774739", "12", env, ok), "refused", "not a valid code");
});
