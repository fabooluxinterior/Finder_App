// POST { media_id }
// Removes one of the caller's photos and deletes its encrypted object from
// storage immediately, so removed photos never sit in the bucket using up the
// storage allowance. (media-maintenance purges anything left behind if this
// delete fails part-way.)
import { admin, rateLimit, requireUser } from "../_shared/auth.ts";
import { handle, HttpError, json } from "../_shared/http.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

Deno.serve((req) =>
  handle(req, async () => {
    if (req.method !== "POST") throw new HttpError(405, "method", "POST only.");
    const { user, asUser } = await requireUser(req);
    await rateLimit(user.id, "photo_remove", 60, 3600);
    const body = await req.json().catch(() => ({}));
    const mediaId = String(body.media_id ?? "");
    if (!UUID.test(mediaId)) throw new HttpError(400, "bad_request", "Invalid photo.");

    // Ownership is checked inside remove_photo (runs as the caller).
    const { data: path, error } = await asUser.rpc("remove_photo", { p_media: mediaId });
    if (error) throw new HttpError(404, "not_found", "Photo not found.");

    const { error: delErr } = await admin.storage.from("media_encrypted").remove([path as string]);
    if (!delErr) await admin.from("media_objects").delete().eq("id", mediaId).eq("status", "deleted");
    return json(req, { removed: mediaId });
  })
);
