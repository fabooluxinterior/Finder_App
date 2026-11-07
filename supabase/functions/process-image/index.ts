// POST { path, kind: "primary" | "gallery" }
// Secure upload pipeline: quarantine -> validate -> decode/re-encode (strips
// EXIF/GPS) -> moderate -> encrypt (AES-256-GCM envelope) -> publish.
import { admin, rateLimit, requireUser, securityEvent } from "../_shared/auth.ts";
import { handle, HttpError, json } from "../_shared/http.ts";
import { RejectedImage, sanitizeImage } from "../_shared/image.ts";
import { sealMedia } from "../_shared/media_crypto.ts";
import { moderate } from "../_shared/moderation.ts";

const PATH = /^[0-9a-f-]{36}\/[0-9a-f-]{36}\.(jpg|png)$/;

Deno.serve((req) =>
  handle(req, async () => {
    if (req.method !== "POST") throw new HttpError(405, "method", "POST only.");
    const { user } = await requireUser(req);
    await rateLimit(user.id, "process_image", 20, 3600);

    const body = await req.json().catch(() => ({}));
    const path = String(body.path ?? "");
    const kind = body.kind === "gallery" ? "gallery" : body.kind === "primary" ? "primary" : null;
    if (!kind || !PATH.test(path) || !path.startsWith(`${user.id}/`)) {
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
      throw new HttpError(422, "rejected", "This photo isn't allowed on Finder.");
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
    });
    if (insErr) {
      await admin.storage.from("media_encrypted").remove([storagePath]);
      throw insErr;
    }

    if (verdict.status === "approved") {
      const { error } = await admin.rpc("attach_media", { p_media: mediaId });
      if (error) throw error;
    }
    return json(req, { media_id: mediaId, status: verdict.status });
  })
);
