import { assert, assertEquals } from "jsr:@std/assert@1";
import { buildMessage, parseServiceAccount, signServiceJwt } from "../fcm.ts";

async function testKeyPem(): Promise<{ pem: string; pub: CryptoKey }> {
  const kp = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", kp.privateKey));
  let s = "";
  for (const b of der) s += String.fromCharCode(b);
  return { pem: `-----BEGIN PRIVATE KEY-----\n${btoa(s)}\n-----END PRIVATE KEY-----\n`, pub: kp.publicKey };
}

Deno.test("service account: missing or incomplete means not configured", () => {
  assertEquals(parseServiceAccount(undefined), null);
  assertEquals(parseServiceAccount("not json"), null);
  assertEquals(parseServiceAccount('{"project_id":"p"}'), null);
  assert(parseServiceAccount('{"project_id":"p","client_email":"e@x","private_key":"k"}'));
});

Deno.test("JWT is RS256, scoped to messaging, one hour, and verifies", async () => {
  const { pem, pub } = await testKeyPem();
  const jwt = await signServiceJwt({ project_id: "p", client_email: "svc@p.iam.gserviceaccount.com", private_key: pem }, 1000);
  const [h, c, sig] = jwt.split(".");
  const dec = (x: string) => JSON.parse(atob(x.replaceAll("-", "+").replaceAll("_", "/")));
  assertEquals(dec(h), { alg: "RS256", typ: "JWT" });
  const claims = dec(c);
  assertEquals(claims.scope, "https://www.googleapis.com/auth/firebase.messaging");
  assertEquals(claims.iss, "svc@p.iam.gserviceaccount.com");
  assertEquals(claims.exp - claims.iat, 3600);
  const raw = Uint8Array.from(atob(sig.replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - (sig.length % 4)) % 4)), (x) => x.charCodeAt(0));
  assert(await crypto.subtle.verify("RSASSA-PKCS1-v1_5", pub, raw, new TextEncoder().encode(`${h}.${c}`)));
});

Deno.test("message carries title and body as a notification (popup)", () => {
  const m = buildMessage("tok", "Hello", "World");
  assertEquals(m.message.notification, { title: "Hello", body: "World" });
  assertEquals(m.message.token, "tok");
});

import { firstName, isUuid, messageNotice, secretMatches } from "../push_message.ts";

Deno.test("chat push: only the sender's first name, never content", () => {
  assertEquals(messageNotice("Anil Krishna"), { title: "Anil", body: "Sent you a message" });
  assertEquals(firstName(""), "Someone");
  assertEquals(firstName(null), "Someone");
  assertEquals(buildMessage("t", "A", "B", { kind: "message", tag: "chat-1" }).message.android, {
    priority: "HIGH",
    notification: { tag: "chat-1" },
  });
});

Deno.test("chat push: shared secret is checked strictly", () => {
  assert(secretMatches("abc123", "abc123"));
  assert(!secretMatches("abc124", "abc123"));
  assert(!secretMatches("abc", "abc123"));
  assert(!secretMatches(null, "abc123"));
  assert(!secretMatches("anything", undefined), "no configured secret means nobody is allowed");
  assert(!secretMatches("", ""));
  assert(isUuid("11111111-2222-3333-4444-555555555555"));
  assert(!isUuid("x"));
});
