import { assert, assertEquals } from "jsr:@std/assert@1";
import { sendTicketEmail, ticketEmail } from "../support_mail.ts";

const t = { ticketNo: "VB-7K3Q9P", category: "subscription", subject: "Trial <b>question</b>",
  description: "When does it end?\n<script>x</script>", userEmail: "asha@example.com", hasAttachment: true };

Deno.test("support mail: escapes user text and keeps the ticket number", () => {
  const m = ticketEmail(t);
  assert(m.subject.startsWith("[Vouby support] VB-7K3Q9P"));
  assert(!m.html.includes("<script>"));
  assert(m.html.includes("&lt;script&gt;"));
});

Deno.test("support mail: not configured -> stored only; key never echoed", async () => {
  assertEquals(await sendTicketEmail(t, () => undefined), "not_configured");
  let auth = "";
  let body = "";
  const env = (k: string) => ({ RESEND_API_KEY: "re_secret_key", SUPPORT_EMAIL_TO: "a@x.com, b@x.com" } as Record<string, string>)[k];
  const r = await sendTicketEmail(t, env, async (_u, init) => {
    auth = new Headers(init?.headers).get("Authorization") ?? "";
    body = String(init?.body);
    return new Response("{}", { status: 200 });
  });
  assertEquals(r, "sent");
  assertEquals(auth, "Bearer re_secret_key");
  assertEquals(JSON.parse(body).to, ["a@x.com", "b@x.com"]);
  assertEquals(JSON.parse(body).reply_to, "asha@example.com");
  assert(!body.includes("re_secret_key"));
  assertEquals(await sendTicketEmail(t, env, async () => new Response("", { status: 500 })), "failed");
});
