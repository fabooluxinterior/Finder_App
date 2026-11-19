import { assertEquals } from "jsr:@std/assert@1";
import { lookup, resetCatalogToken, searchArtists } from "../spotify_catalog.ts";

const fake = (routes: Record<string, unknown>): typeof fetch => (input) => {
  const u = String(input);
  if (u.includes("/api/token")) return Promise.resolve(new Response(JSON.stringify({ access_token: "t", expires_in: 3600 })));
  for (const [k, v] of Object.entries(routes)) if (u.includes(k)) return Promise.resolve(new Response(JSON.stringify(v)));
  return Promise.resolve(new Response("{}", { status: 404 }));
};

Deno.test("search keeps only valid artists and Spotify images", async () => {
  Deno.env.set("SPOTIFY_CLIENT_ID", "id");
  Deno.env.set("SPOTIFY_CLIENT_SECRET", "secret");
  resetCatalogToken();
  const f = fake({
    "/search": { artists: { items: [
      { id: "4Z8W4fKeB5YxbusRsdQVPb", name: "Radiohead", images: [{ url: "https://i.scdn.co/image/abc", width: 320 }], genres: ["rock"] },
      { id: "bad", name: "Nope" },
      { id: "1dfeR4HaWDbWqFHLkxsg1d", name: "Queen", images: [{ url: "https://evil.example/x.png" }] },
    ] } },
  });
  const r = await searchArtists("rad", f);
  assertEquals(r.map((a) => a.name), ["Radiohead", "Queen"]);
  assertEquals(r[1].image, null);
});

Deno.test("lookup ignores bad ids and nulls from Spotify", async () => {
  resetCatalogToken();
  const f = fake({
    "/artists": { artists: [null, { id: "1dfeR4HaWDbWqFHLkxsg1d", name: "Queen", images: [] }] },
    "/tracks": { tracks: [{ id: "11dFghVXANMlKmJXsNCbNl", name: "Song", artists: [{ name: "A" }], album: {} }, null] },
  });
  const r = await lookup(["1dfeR4HaWDbWqFHLkxsg1d", "../x"], ["11dFghVXANMlKmJXsNCbNl"], f);
  assertEquals(r.artists.length, 1);
  assertEquals(r.tracks.length, 1);
});
