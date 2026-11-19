// POST: permanently deletes the caller's account. Requires an MFA session
// when the user has MFA enrolled (checked by prepare_account_deletion).
import { admin, requireUser } from "../_shared/auth.ts";
import { handle, HttpError, json } from "../_shared/http.ts";

Deno.serve((req) =>
  handle(req, async () => {
    if (req.method !== "POST") throw new HttpError(405, "method", "POST only.");
    const { user, asUser } = await requireUser(req);
    const { data: paths, error } = await asUser.rpc("prepare_account_deletion");
    if (error) throw new HttpError(403, "mfa_required", error.message);

    const media = (paths as string[] | null) ?? [];
    for (let i = 0; i < media.length; i += 100) {
      await admin.storage.from("media_encrypted").remove(media.slice(i, i + 100));
    }
    // Voice-note ciphertext in any conversation folder this user belongs to.
    const { data: folders } = await admin.storage.from("voice_notes").list("", { limit: 1000 });
    for (const f of folders ?? []) {
      if (!f.name.split("_").includes(user.id)) continue;
      const { data: files } = await admin.storage.from("voice_notes").list(f.name, { limit: 1000 });
      if (files?.length) await admin.storage.from("voice_notes").remove(files.map((x) => `${f.name}/${x.name}`));
    }
    // Cascades: profile, devices, keys, messages, envelopes, swipes, reports filed.
    const { error: delErr } = await admin.auth.admin.deleteUser(user.id);
    if (delErr) throw delErr;
    return json(req, { deleted: true });
  })
);
