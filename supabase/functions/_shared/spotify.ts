// Spotify Web API client for the music connector (Authorization Code flow,
// scope user-top-read; CSRF protection via a one-time `state`). Runs only inside edge functions: the
// client secret, codes and tokens never reach the app.
export const SCOPE = "user-top-read";
const ACCOUNTS = "https://accounts.spotify.com";
const API = "https://api.spotify.com/v1";

export type Artist = { id: string; name: string; image: string | null; genres: string[] };
export type Tokens = { access: string; refresh: string | null };

export class ReauthRequired extends Error {}
export class SpotifyRateLimited extends Error {
  constructor(public retryAfter: number) {
    super("rate limited");
  }
}

type Fetch = typeof fetch;

export function config() {
  const clientId = Deno.env.get("SPOTIFY_CLIENT_ID") ?? "";
  const clientSecret = Deno.env.get("SPOTIFY_CLIENT_SECRET") ?? "";
  const redirectUri = Deno.env.get("SPOTIFY_REDIRECT_URI") ?? "";
  if (!clientId || !clientSecret || !redirectUri.startsWith("https://")) throw new Error("Spotify is not configured");
  return { clientId, clientSecret, redirectUri };
}

const b64url = (u: Uint8Array) => btoa(String.fromCharCode(...u)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

export function randomToken(bytes = 32) {
  return b64url(crypto.getRandomValues(new Uint8Array(bytes)));
}

export function authorizeUrl(state: string) {
  const { clientId, redirectUri } = config();
  const q = new URLSearchParams({
    response_type: "code",
    client_id: clientId,
    scope: SCOPE,
    redirect_uri: redirectUri,
    state,
    show_dialog: "true", // always show the consent screen, so the user sees exactly what's shared
  });
  return `${ACCOUNTS}/authorize?${q}`;
}

async function tokenRequest(body: Record<string, string>, f: Fetch): Promise<Tokens> {
  const { clientId, clientSecret } = config();
  const res = await f(`${ACCOUNTS}/api/token`, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization: `Basic ${btoa(`${clientId}:${clientSecret}`)}`,
    },
    body: new URLSearchParams(body),
  });
  if (res.status === 400 || res.status === 401) {
    const err = await res.json().catch(() => ({}));
    if (err.error === "invalid_grant" || err.error === "invalid_client") throw new ReauthRequired(err.error);
  }
  if (res.status === 429) throw new SpotifyRateLimited(Number(res.headers.get("Retry-After") ?? "30"));
  if (!res.ok) throw new Error(`token endpoint ${res.status}`);
  const j = await res.json();
  if (typeof j.access_token !== "string") throw new Error("no access token");
  return { access: j.access_token, refresh: typeof j.refresh_token === "string" ? j.refresh_token : null };
}

export function exchangeCode(code: string, f: Fetch = fetch) {
  const { redirectUri } = config();
  return tokenRequest({ grant_type: "authorization_code", code, redirect_uri: redirectUri }, f);
}

/** Refresh-token rotation: Spotify may return a new refresh token; the caller
 *  must store it (and stop using the old one) when `refresh` is non-null. */
export function refreshAccess(refreshToken: string, f: Fetch = fetch) {
  return tokenRequest({ grant_type: "refresh_token", refresh_token: refreshToken }, f);
}

/** Medium image: the one closest to 320 px wide (Spotify lists 640/320/160). */
export function pickImage(images: { url?: string; width?: number | null }[] | undefined): string | null {
  const valid = (images ?? []).filter((i) => typeof i.url === "string" && i.url.startsWith("https://i.scdn.co/image/"));
  if (!valid.length) return null;
  valid.sort((a, b) => Math.abs((a.width ?? 320) - 320) - Math.abs((b.width ?? 320) - 320));
  return valid[0].url!;
}

export function mapArtists(items: unknown): Artist[] {
  if (!Array.isArray(items)) return [];
  return items.slice(0, 10).flatMap((it) => {
    const a = it as { id?: unknown; name?: unknown; images?: { url?: string; width?: number }[]; genres?: unknown };
    if (typeof a.id !== "string" || !/^[A-Za-z0-9]{10,40}$/.test(a.id) || typeof a.name !== "string" || !a.name) return [];
    const genres = Array.isArray(a.genres) ? a.genres.filter((g): g is string => typeof g === "string").slice(0, 5) : [];
    return [{ id: a.id, name: a.name.slice(0, 80), image: pickImage(a.images), genres }];
  });
}

/** Top 10 artists over roughly the last six months. An empty list (new or
 *  quiet accounts) is a valid result, not an error. */
export async function topArtists(access: string, f: Fetch = fetch): Promise<Artist[]> {
  const res = await f(`${API}/me/top/artists?limit=10&time_range=medium_term`, {
    headers: { Authorization: `Bearer ${access}` },
  });
  if (res.status === 401) throw new ReauthRequired("access token rejected");
  if (res.status === 429) throw new SpotifyRateLimited(Number(res.headers.get("Retry-After") ?? "30"));
  if (!res.ok) throw new Error(`top artists ${res.status}`);
  const j = await res.json();
  return mapArtists(j.items);
}
