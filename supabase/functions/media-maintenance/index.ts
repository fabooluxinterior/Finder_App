// Service-only maintenance (call from a scheduled job with the service key):
//   POST { task: "purge" }   delete encrypted objects of removed media
//   POST { task: "rewrap" }  re-wrap data keys under MEDIA_KEK_ACTIVE (KEK rotation)
import { admin } from "../_shared/auth.ts";
import { handle, HttpError, json } from "../_shared/http.ts";
import { rewrapDek } from "../_shared/media_crypto.ts";

Deno.serve((req) =>
  handle(req, async () => {
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    if (req.headers.get("Authorization") !== `Bearer ${key}`) throw new HttpError(401, "unauthenticated", "Service only.");
    const { task } = await req.json();

    if (task === "purge") {
      const { data } = await admin.from("media_objects").select("id, storage_path").eq("status", "deleted").limit(500);
      if (data?.length) {
        await admin.storage.from("media_encrypted").remove(data.map((r) => r.storage_path));
        await admin.from("media_objects").delete().in("id", data.map((r) => r.id));
      }
      return json(req, { purged: data?.length ?? 0 });
    }

    if (task === "rewrap") {
      const active = Deno.env.get("MEDIA_KEK_ACTIVE");
      const { data } = await admin.from("media_objects").select("id, wrapped_dek, kek_id").neq("kek_id", active).limit(500);
      let n = 0;
      for (const r of data ?? []) {
        const next = await rewrapDek(r.id, r.wrapped_dek, r.kek_id);
        if (!next) continue;
        await admin.from("media_objects").update({ wrapped_dek: next.wrappedDek, kek_id: next.kekId })
          .eq("id", r.id).eq("kek_id", r.kek_id);
        n++;
      }
      return json(req, { rewrapped: n, remaining: Math.max(0, (data?.length ?? 0) - n) });
    }
    throw new HttpError(400, "bad_request", "Unknown task.");
  })
);
