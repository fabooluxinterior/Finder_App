// GET /functions/v1/media/<media-id>   (Authorization: Bearer <user JWT>)
// The only way to read a stored image. Authorises every request on the
// server, decrypts, and streams with private, short-lived caching. Storage
// URLs are never handed to clients, so copied links don't work.
import { admin, rateLimit, requireUser, securityEvent } from "../_shared/auth.ts";
import { corsHeaders, handle, HttpError } from "../_shared/http.ts";
import { openMedia } from "../_shared/media_crypto.ts";

// The JWT was already verified by requireUser(); read its assurance level.
function aal(req: Request): string {
  try {
    const payload = (req.headers.get("Authorization") ?? "").split(".")[1];
    return JSON.parse(atob(payload.replace(/-/g, "+").replace(/_/g, "/"))).aal ?? "aal1";
  } catch {
    return "aal1";
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

Deno.serve((req) =>
  handle(req, async () => {
    if (req.method !== "GET") throw new HttpError(405, "method", "GET only.");
    const id = new URL(req.url).pathname.split("/").pop() ?? "";
    if (!UUID.test(id)) throw new HttpError(404, "not_found", "Not found.");

    const { user } = await requireUser(req);
    try {
      await rateLimit(user.id, "media_get", 600, 3600);
    } catch (e) {
      await securityEvent(user.id, "media_download_spike", "warning", {});
      throw e;
    }

    const { data: allowedRaw } = await admin.rpc("can_view_media", { p_viewer: user.id, p_media: id });
    let allowed = allowedRaw === true;
    if (!allowed && aal(req) === "aal2") {
      // Moderators reviewing held images: MFA session required, every view audited.
      const { data: role } = await admin.rpc("staff_role_of", { p_user: user.id });
      if (role === "moderator" || role === "admin") {
        allowed = true;
        await admin.from("access_audit_log").insert({
          actor_id: user.id, action: "view_media", target_type: "media", target_id: id,
        });
      }
    }
    if (!allowed) {
      await securityEvent(user.id, "media_access_denied", "info", { media: id });
      throw new HttpError(404, "not_found", "Not found."); // don't reveal existence
    }

    const { data: row } = await admin.from("media_objects")
      .select("storage_path, wrapped_dek, kek_id, nonce, sha256").eq("id", id).single();
    const { data: blob } = await admin.storage.from("media_encrypted").download(row!.storage_path);
    if (!blob) throw new HttpError(404, "not_found", "Not found.");
    const plain = await openMedia(id, row!, new Uint8Array(await blob.arrayBuffer()));

    return new Response(plain, {
      headers: {
        ...corsHeaders(req),
        // The web app runs cross-origin isolated (COEP); access control is the
        // Authorization header, which a plain <img> embed can't send.
        "Cross-Origin-Resource-Policy": "cross-origin",
        "Content-Type": "image/webp",
        "Content-Disposition": "inline",
        "Cache-Control": "private, max-age=300, no-transform",
        "Content-Security-Policy": "default-src 'none'; sandbox",
      },
    });
  })
);
