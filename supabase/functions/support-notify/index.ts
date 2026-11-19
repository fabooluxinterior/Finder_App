// POST { ticket_id } — called by the app right after submit_support_ticket.
// Emails staff about the caller's own new ticket (if email is configured).
// The ticket is already stored either way; this only notifies.
import { admin, rateLimit, requireUser } from "../_shared/auth.ts";
import { handle, HttpError, json } from "../_shared/http.ts";
import { sendTicketEmail } from "../_shared/support_mail.ts";

Deno.serve((req) =>
  handle(req, async () => {
    if (req.method !== "POST") throw new HttpError(405, "method", "POST only.");
    const { user } = await requireUser(req);
    await rateLimit(user.id, "support_notify", 10, 86400);
    const { ticket_id } = await req.json().catch(() => ({}));
    if (typeof ticket_id !== "string") throw new HttpError(400, "bad_request", "ticket_id required.");
    const { data: t } = await admin.from("support_tickets")
      .select("ticket_no, category, subject, description, email, attachment_path, user_id, created_at")
      .eq("id", ticket_id).maybeSingle();
    // Only the owner, only for a just-created ticket (no re-sending old ones).
    if (!t || t.user_id !== user.id || Date.now() - Date.parse(t.created_at) > 10 * 60_000) {
      throw new HttpError(404, "not_found", "Ticket not found.");
    }
    const result = await sendTicketEmail({
      ticketNo: t.ticket_no, category: t.category, subject: t.subject, description: t.description,
      userEmail: t.email, hasAttachment: !!t.attachment_path,
    }, (n) => Deno.env.get(n));
    return json(req, { notified: result });
  }));
