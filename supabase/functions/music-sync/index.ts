// POST { action: "sync", force? } | { action: "disconnect" }
// sync: refreshes the imported top artists at most every 12 hours (feeds and
//   swipes never call Spotify; they read the stored list). Rotated refresh
//   tokens are stored; a revoked token marks the account "reauth_required".
// disconnect: deletes tokens and imported artists, and clears the profile.
import { admin, rateLimit, requireUser } from "../_shared/auth.ts";
import { handle, HttpError, json } from "../_shared/http.ts";
import { openSecret, sealSecret } from "../_shared/media_crypto.ts";
import { ReauthRequired, refreshAccess, SpotifyRateLimited, topArtists } from "../_shared/spotify.ts";

const FRESH_MS = 12 * 3600_000;

Deno.serve((req) =>
  handle(req, async () => {
    if (req.method !== "POST") throw new HttpError(405, "method", "POST only.");
    const { user, asUser } = await requireUser(req);
    await rateLimit(user.id, "music_sync", 30, 3600);
    const body = await req.json().catch(() => ({}));

    if (body.action === "disconnect") {
      const { error } = await asUser.rpc("disconnect_music");
      if (error) throw error;
      return json(req, { status: "disconnected" });
    }
    if (body.action !== "sync") throw new HttpError(400, "bad_request", "Unknown action.");

    const { data: acct } = await admin.from("music_accounts")
      .select("refresh_token_enc, kek_id, status, synced_at").eq("user_id", user.id).maybeSingle();
    if (!acct) return json(req, { status: "disconnected" });
    if (acct.status === "reauth_required" || !acct.refresh_token_enc || !acct.kek_id) {
      return json(req, { status: "reauth_required" });
    }
    const age = acct.synced_at ? Date.now() - new Date(acct.synced_at).getTime() : Infinity;
    if (age < FRESH_MS && body.force !== true) return json(req, { status: "cached" });

    try {
      const refresh = await openSecret(`music:${user.id}`, acct.refresh_token_enc, acct.kek_id);
      const tokens = await refreshAccess(refresh);
      const artists = await topArtists(tokens.access);
      const rotated = tokens.refresh && tokens.refresh !== refresh ? await sealSecret(`music:${user.id}`, tokens.refresh) : null;
      const { error } = await admin.rpc("service_music_store", {
        p_user: user.id, p_token_enc: rotated?.sealed ?? null, p_kek: rotated?.kekId ?? null, p_artists: artists,
      });
      if (error) throw error;
      return json(req, { status: "synced", count: artists.length });
    } catch (e) {
      if (e instanceof ReauthRequired) {
        await admin.rpc("service_music_reauth", { p_user: user.id });
        return json(req, { status: "reauth_required" });
      }
      // Rate-limited or Spotify unavailable: keep showing the stored list.
      if (e instanceof SpotifyRateLimited) return json(req, { status: "cached", retry_after: e.retryAfter });
      console.error("music sync", e instanceof Error ? e.name : "error");
      return json(req, { status: "cached" });
    }
  })
);
