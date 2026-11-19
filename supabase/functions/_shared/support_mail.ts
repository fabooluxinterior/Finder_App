// Builds and sends the "new support ticket" email to staff. Pure helpers so
// they're testable; the API key never leaves the server and never appears in
// a response or error message.

export interface TicketMail {
  ticketNo: string;
  category: string;
  subject: string;
  description: string;
  userEmail: string | null;
  hasAttachment: boolean;
}

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

export function ticketEmail(t: TicketMail) {
  const subject = `[Vouby support] ${t.ticketNo} · ${t.category} · ${t.subject}`.slice(0, 200);
  const text = [
    `Ticket: ${t.ticketNo}`,
    `Category: ${t.category}`,
    `From: ${t.userEmail ?? "(no email on the account)"}`,
    `Screenshot: ${t.hasAttachment ? "yes (open it in the staff dashboard)" : "no"}`,
    "",
    t.description,
  ].join("\n");
  const html = `<p><b>Ticket:</b> ${esc(t.ticketNo)}<br><b>Category:</b> ${esc(t.category)}<br>` +
    `<b>From:</b> ${esc(t.userEmail ?? "(no email)")}<br><b>Screenshot:</b> ${t.hasAttachment ? "yes" : "no"}</p>` +
    `<p>${esc(t.description).replace(/\n/g, "<br>")}</p>`;
  return { subject, text, html };
}

export type Env = (name: string) => string | undefined;

/** Sends via Resend when RESEND_API_KEY + SUPPORT_EMAIL_TO are set; otherwise
 *  reports "not_configured" (tickets are still stored and shown to staff). */
export async function sendTicketEmail(t: TicketMail, env: Env, f: typeof fetch = fetch): Promise<"sent" | "not_configured" | "failed"> {
  const key = env("RESEND_API_KEY");
  const to = env("SUPPORT_EMAIL_TO");
  if (!key || !to) return "not_configured";
  const from = env("SUPPORT_EMAIL_FROM") ?? "Vouby Support <onboarding@resend.dev>";
  const mail = ticketEmail(t);
  try {
    const res = await f("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from, to: to.split(",").map((s) => s.trim()).filter(Boolean),
        subject: mail.subject, text: mail.text, html: mail.html,
        ...(t.userEmail ? { reply_to: t.userEmail } : {}),
      }),
    });
    await res.body?.cancel();
    return res.ok ? "sent" : "failed";
  } catch (_) {
    return "failed";
  }
}
