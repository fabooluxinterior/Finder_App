// POST {}  ->  { url }
// Starts "Connect Spotify": stores a one-time state for the signed-in user and
// returns Spotify's consent URL. The app opens it in the browser; Spotify then
// redirects to music-callback, which finishes everything server-side.
import { admin, rateLimit, requireUser } from "../_shared/auth.ts";
import { handle, HttpError, json } from "../_shared/http.ts";
import { authorizeUrl, randomToken } from "../_shared/spotify.ts";

Deno.serve((req) =>
  handle(req, async () => {
    if (req.method !== "POST") throw new HttpError(405, "method", "POST only.");
    const { user } = await requireUser(req);
    await rateLimit(user.id, "music_connect", 10, 3600);
    await admin.rpc("purge_music_states");
    const state = randomToken(32);
    const { error } = await admin.from("music_oauth_states").insert({ state, user_id: user.id });
    if (error) throw error;
    let url: string;
    try {
      url = authorizeUrl(state);
    } catch {
      throw new HttpError(503, "not_configured", "Spotify isn't available right now.");
    }
    return json(req, { url });
  })
);
