// Spotify catalogue (search + lookup by id) with the app's own token (Client Credentials). No user login, so it
// is not subject to the development-mode user limit. Runs only inside edge functions: the client secret never
// reaches the app. Results go through the same mappers as the login flow (ids checked, Spotify CDN images only).
import { type Artist, mapArtists, mapTrack, type Track } from "./spotify.ts";

type Fetch = typeof fetch;
const API = "https://api.spotify.com/v1";
const ID = /^[A-Za-z0-9]{10,40}$/;

let cached: { token: string; until: number } | null = null;

export function catalogConfigured(): boolean {
  return !!Deno.env.get("SPOTIFY_CLIENT_ID") && !!Deno.env.get("SPOTIFY_CLIENT_SECRET");
}

export async function appToken(f: Fetch = fetch): Promise<string> {
  if (cached && Date.now() < cached.until) return cached.token;
  const id = Deno.env.get("SPOTIFY_CLIENT_ID") ?? "";
  const secret = Deno.env.get("SPOTIFY_CLIENT_SECRET") ?? "";
  if (!id || !secret) throw new Error("Spotify is not configured");
  const res = await f("https://accounts.spotify.com/api/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", Authorization: `Basic ${btoa(`${id}:${secret}`)}` },
    body: new URLSearchParams({ grant_type: "client_credentials" }),
  });
  if (!res.ok) throw new Error(`app token ${res.status}`);
  const j = await res.json();
  if (typeof j.access_token !== "string") throw new Error("no access token");
  cached = { token: j.access_token, until: Date.now() + Math.max(60, Number(j.expires_in ?? 3600) - 60) * 1000 };
  return cached.token;
}

export function resetCatalogToken() {
  cached = null;
}

async function get(path: string, f: Fetch): Promise<Record<string, unknown>> {
  const res = await f(`${API}${path}`, { headers: { Authorization: `Bearer ${await appToken(f)}` } });
  if (!res.ok) throw new Error(`spotify ${res.status}`);
  return await res.json();
}

export async function searchArtists(q: string, f: Fetch = fetch): Promise<Artist[]> {
  const j = await get(`/search?${new URLSearchParams({ q, type: "artist", limit: "10" })}`, f);
  return mapArtists((j.artists as { items?: unknown } | undefined)?.items);
}

export async function searchTracks(q: string, f: Fetch = fetch): Promise<Track[]> {
  const j = await get(`/search?${new URLSearchParams({ q, type: "track", limit: "10" })}`, f);
  const items = (j.tracks as { items?: unknown[] } | undefined)?.items;
  return (Array.isArray(items) ? items : []).map(mapTrack).filter((t): t is Track => !!t);
}

/** Looks the picks up again by id, so what is stored is what Spotify says, never what the phone sent. */
export async function lookup(artistIds: string[], trackIds: string[], f: Fetch = fetch) {
  const a = [...new Set(artistIds)].filter((x) => ID.test(x)).slice(0, 10);
  const t = [...new Set(trackIds)].filter((x) => ID.test(x)).slice(0, 10);
  const artists = a.length ? mapArtists(((await get(`/artists?ids=${a.join(",")}`, f)).artists as unknown[] | undefined)?.filter(Boolean)) : [];
  const tracksRaw = t.length ? ((await get(`/tracks?ids=${t.join(",")}`, f)).tracks as unknown[] | undefined) ?? [] : [];
  const tracks = tracksRaw.map(mapTrack).filter((x): x is Track => !!x);
  return { artists, tracks };
}
