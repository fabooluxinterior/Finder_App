// POST { action: "search", q } -> { artists, tracks }
//      { action: "save", artist_ids, track_ids } -> stores the picks as the person's music card
// For people who don't want to log in to Spotify. Uses the app's own Spotify token, so the 25-user development
// limit does not apply. A save replaces the stored lists; the details are fetched from Spotify again by id.
import { admin, rateLimit, requireUser } from "../_shared/auth.ts";
import { handle, HttpError, json } from "../_shared/http.ts";
import { catalogConfigured, lookup, searchArtists, searchTracks } from "../_shared/spotify_catalog.ts";

Deno.serve((req) =>
  handle(req, async () => {
    if (req.method !== "POST") throw new HttpError(405, "method", "POST only.");
    const { user } = await requireUser(req);
    if (!catalogConfigured()) throw new HttpError(503, "not_configured", "Music search isn't available right now.");
    const body = await req.json().catch(() => ({}));

    if (body.action === "search") {
      await rateLimit(user.id, "music_pick_search", 120, 3600);
      const q = typeof body.q === "string" ? body.q.trim().slice(0, 80) : "";
      if (q.length < 2) return json(req, { artists: [], tracks: [] });
      try {
        const [artists, tracks] = await Promise.all([searchArtists(q), searchTracks(q)]);
        return json(req, { artists, tracks });
      } catch (e) {
        console.error("music search", e instanceof Error ? e.name : "error");
        throw new HttpError(502, "upstream", "Couldn't reach Spotify. Try again.");
      }
    }

    if (body.action === "save") {
      await rateLimit(user.id, "music_pick_save", 30, 3600);
      const ids = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : []);
      try {
        const { artists, tracks } = await lookup(ids(body.artist_ids), ids(body.track_ids));
        const { error } = await admin.rpc("service_music_store_v2", {
          p_user: user.id, p_token_enc: null, p_kek: null,
          p_artists: artists, p_tracks: tracks, p_recent: [], p_scopes: null,
        });
        if (error) throw error;
        return json(req, { status: "saved", artists: artists.length, tracks: tracks.length });
      } catch (e) {
        console.error("music save", e instanceof Error ? e.name : "error");
        throw new HttpError(502, "upstream", "Couldn't save your picks. Try again.");
      }
    }
    throw new HttpError(400, "bad_request", "Unknown action.");
  })
);
