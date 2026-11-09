// GET ?code=…&state=…  (Spotify's redirect target; set as SPOTIFY_REDIRECT_URI)
// Exchanges the one-time code for tokens server-side, imports the top 10
// artists, stores the refresh token encrypted, and sends the user back to the
// app. Nothing secret appears in the URL the app receives.
import { admin, securityEvent } from "../_shared/auth.ts";
import { sealSecret } from "../_shared/media_crypto.ts";
import { exchangeCode, importAll, ReauthRequired } from "../_shared/spotify.ts";

const RETURN = Deno.env.get("MUSIC_RETURN_URL") ?? "vouby://music";

function page(status: "connected" | "cancelled" | "error", message: string) {
  const back = `${RETURN}?status=${status}`;
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Vouby</title>
<style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0B0B0C;color:#F5F5F5;font:16px/1.5 system-ui,sans-serif;text-align:center;padding:24px;box-sizing:border-box}
a{display:inline-block;margin-top:20px;padding:14px 26px;border-radius:999px;background:#FF5A3D;color:#0B0B0C;font-weight:600;text-decoration:none}</style>
</head><body><main><p>${message}</p><a href="${back}">Back to Vouby</a></main>
<script>setTimeout(function(){location.href=${JSON.stringify(back)}},300)</script></body></html>`;
  return new Response(html, {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
      "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'",
    },
  });
}

Deno.serve(async (req) => {
  const u = new URL(req.url);
  const state = u.searchParams.get("state") ?? "";
  const code = u.searchParams.get("code");
  if (req.method !== "GET" || state.length < 32) return page("error", "That link has expired. Try connecting again from the app.");

  // One-time state: deleted as it's read, valid for 10 minutes.
  const { data: row } = await admin.from("music_oauth_states").delete().eq("state", state).select("user_id, created_at").maybeSingle();
  if (!row || Date.now() - new Date(row.created_at).getTime() > 10 * 60_000) {
    await securityEvent(null, "music_oauth_state_rejected", "warning", {});
    return page("error", "That link has expired. Try connecting again from the app.");
  }
  if (!code) return page("cancelled", "Spotify wasn't connected. You can try again any time.");

  try {
    const tokens = await exchangeCode(code);
    const { artists, tracks, recent } = await importAll(tokens.access);
    const sealed = tokens.refresh ? await sealSecret(`music:${row.user_id}`, tokens.refresh) : null;
    const { error } = await admin.rpc("service_music_store_v2", {
      p_user: row.user_id, p_token_enc: sealed?.sealed ?? null, p_kek: sealed?.kekId ?? null,
      p_artists: artists, p_tracks: tracks, p_recent: recent, p_scopes: tokens.scope,
    });
    if (error) throw error;
    return page("connected", artists.length || tracks.length
      ? "Spotify is connected. Your music is on your profile."
      : "Spotify is connected. Listen a little more and your music will appear soon.");
  } catch (e) {
    console.error("music callback", e instanceof ReauthRequired ? "rejected" : e instanceof Error ? e.name : "error");
    return page("error", "We couldn't connect Spotify. Please try again.");
  }
});
