// POST { path, kind: "photo" | "primary" | "gallery" | "selfie", replaces?, request_id? }
//   kind "photo": one of the 6 profile slots; `replaces` swaps a slot in place
//   and the old encrypted object is deleted from storage immediately.
// Secure upload pipeline: quarantine -> validate -> decode/re-encode (strips
// EXIF/GPS) -> moderate -> encrypt (AES-256-GCM envelope) -> publish.
import { admin, rateLimit, requireUser, securityEvent } from "../_shared/auth.ts";
import { handle, HttpError, json } from "../_shared/http.ts";
import { RejectedImage, sanitizeImage } from "../_shared/image.ts";
import { sealMedia } from "../_shared/media_crypto.ts";
import { moderate } from "../_shared/moderation.ts";

const PATH = /^[0-9a-f-]{36}\/[0-9a-f-]{36}\.(jpg|png|webp)$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

Deno.serve((req) =>
  handle(req, async () => {
    if (req.method !== "POST") throw new HttpError(405, "method", "POST only.");
    const { user } = await requireUser(req);
    await rateLimit(user.id, "process_image", 20, 3600);

    const body = await req.json().catch(() => ({}));
    const path = String(body.path ?? "");
    const kind = ["photo", "primary", "gallery", "selfie"].includes(body.kind) ? (body.kind as string) : null;
    const requestId = String(body.request_id ?? "");
    const replaces = body.replaces == null ? null : String(body.replaces);
    if (!kind || !PATH.test(path) || !path.startsWith(`${user.id}/`) || (kind === "selfie" && !UUID.test(requestId))
        || (replaces !== null && (kind !== "photo" || !UUID.test(replaces)))) {
      await securityEvent(user.id, "upload_path_rejected", "warning", {});
      throw new HttpError(400, "bad_request", "Invalid upload.");
    }

    const { data: blob, error: dlErr } = await admin.storage.from("uploads_quarantine").download(path);
    // The quarantine copy is removed whatever happens next.
    await admin.storage.from("uploads_quarantine").remove([path]);
    if (dlErr || !blob) throw new HttpError(404, "not_found", "Upload not found.");

    let clean;
    try {
      clean = await sanitizeImage(new Uint8Array(await blob.arrayBuffer()));
    } catch (e) {
      if (e instanceof RejectedImage) {
        await securityEvent(user.id, "upload_rejected", "info", { reason: e.message });
        throw new HttpError(422, "rejected", e.message);
      }
      throw e;
    }

    const verdict = await moderate(clean.webp);
    if (verdict.status === "rejected") {
      await securityEvent(user.id, "upload_blocked_by_moderation", "warning", {});
      throw new HttpError(422, "rejected", "This photo isn't allowed on Vouby.");
    }

    const mediaId = crypto.randomUUID();
    const sealed = await sealMedia(mediaId, clean.webp);
    const storagePath = `${user.id}/${mediaId}.bin`;
    const { error: upErr } = await admin.storage.from("media_encrypted")
      .upload(storagePath, sealed.ciphertext, { contentType: "application/octet-stream", upsert: false });
    if (upErr) throw upErr;

    const { error: insErr } = await admin.from("media_objects").insert({
      id: mediaId, owner_id: user.id, kind, status: verdict.status, storage_path: storagePath,
      wrapped_dek: sealed.wrappedDek, kek_id: sealed.kekId, nonce: sealed.nonce, sha256: sealed.sha256,
      width: clean.width, height: clean.height, bytes: clean.webp.length, moderation: verdict.labels,
      reviewed_at: verdict.status === "approved" ? new Date().toISOString() : null,
      replaces,
    });
    if (insErr) {
      await admin.storage.from("media_encrypted").remove([storagePath]);
      throw insErr;
    }

    if (kind === "selfie") {
      // Verification selfies are never published: linked to the pending
      // request for staff review and purged 30 days after review.
      const { error } = await admin.rpc("attach_verification_selfie", { p_user: user.id, p_request: requestId, p_media: mediaId });
      if (error) {
        await admin.from("media_objects").update({ status: "deleted" }).eq("id", mediaId);
        throw new HttpError(409, "expired", "That verification expired. Start again.");
      }
      return json(req, { media_id: mediaId, status: "pending" });
    }

    if (kind === "photo" && replaces) {
      // Only the owner's own published photo can be replaced.
      const { data: old } = await admin.from("media_objects").select("owner_id, status").eq("id", replaces).maybeSingle();
      if (!old || old.owner_id !== user.id || old.status === "deleted") {
        await discard(mediaId, storagePath);
        throw new HttpError(404, "not_found", "That photo is no longer on your profile.");
      }
    }

    if (verdict.status === "approved") {
      const { data: dead, error } = await admin.rpc("attach_media", { p_media: mediaId });
      if (error) {
        await discard(mediaId, storagePath);
        if (error.hint === "PHOTO_SLOTS_FULL") throw new HttpError(409, "slots_full", "All 6 photo slots are full.");
        throw error;
      }
      // Storage hygiene: a replaced photo's object is deleted right away.
      const paths = (dead as string[] | null) ?? [];
      if (paths.length) await admin.storage.from("media_encrypted").remove(paths);
    }
    return json(req, { media_id: mediaId, status: verdict.status });
  })
);

async function discard(mediaId: string, storagePath: string) {
  await admin.from("media_objects").update({ status: "deleted" }).eq("id", mediaId);
  await admin.storage.from("media_encrypted").remove([storagePath]);
}
