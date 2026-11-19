// Staff only: POST { kind: "evidence", id, reason } | { kind: "ticket", id }
// Returns a 5-minute signed URL for one report-evidence file or one support
// screenshot. The database checks staff + MFA and logs the access
// (mod_evidence_path / mod_ticket_attachment_path) before anything is signed.
import { admin, requireUser } from "../_shared/auth.ts";
import { handle, HttpError, json } from "../_shared/http.ts";

const TTL_SECONDS = 300;

Deno.serve((req) =>
  handle(req, async () => {
    if (req.method !== "POST") throw new HttpError(405, "method", "POST only.");
    const { asUser } = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    if (typeof body.id !== "string") throw new HttpError(400, "bad_request", "id required.");
    let bucket: string;
    let path: string | null;
    if (body.kind === "evidence") {
      bucket = "report_evidence";
      const { data, error } = await asUser.rpc("mod_evidence_path", { p_evidence: body.id, p_reason: String(body.reason ?? "review").slice(0, 200) });
      if (error) throw new HttpError(403, "forbidden", "Staff only (with two-step verification).");
      path = data as string;
    } else if (body.kind === "ticket") {
      bucket = "support_attachments";
      const { data, error } = await asUser.rpc("mod_ticket_attachment_path", { p_ticket: body.id });
      if (error) throw new HttpError(403, "forbidden", "Staff only (with two-step verification).");
      path = data as string;
    } else {
      throw new HttpError(400, "bad_request", "Unknown kind.");
    }
    const { data: signed, error } = await admin.storage.from(bucket).createSignedUrl(path!, TTL_SECONDS);
    if (error || !signed) throw new HttpError(404, "not_found", "File not found.");
    return json(req, { url: signed.signedUrl, expires_in: TTL_SECONDS });
  }));
