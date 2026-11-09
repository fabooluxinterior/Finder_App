import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import encodeWebp from "npm:@jsquash/webp@1.5.0/encode.js";
import { fitBox, RejectedImage, sanitizeImage, sniff, stripWebp, webpInfo } from "../image.ts";
import { openMedia, openSecret, resetKeyringForTests, rewrapDek, sealMedia, sealSecret } from "../media_crypto.ts";
import {
  authorizeUrl, exchangeCode, importAll, mapArtists, mapTrack, pickImage, ReauthRequired, recentlyPlayed, refreshAccess,
  ScopeMissing, SpotifyRateLimited, topArtists,
} from "../spotify.ts";
import { decide } from "../moderation.ts";

const dir = new URL(".", import.meta.url);
const key = () => btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))));

Deno.test("image: re-encodes JPEG to WebP inside 1080 px and strips EXIF/GPS", async () => {
  const src = await Deno.readFile(new URL("gps.jpg", dir));
  assert(new TextDecoder("latin1").decode(src).includes("SecretPhone"));
  const out = await sanitizeImage(src);
  assert(Math.max(out.width, out.height) <= 1080);
  const text = new TextDecoder("latin1").decode(out.webp);
  assert(text.startsWith("RIFF") && text.slice(8, 12) === "WEBP");
  assert(!text.includes("SecretPhone") && !text.includes("Exif") && !text.includes("GPS"));
  assert(out.webp.length <= 100 * 1024);
});

Deno.test("image: rejects files whose bytes aren't a real image, whatever the name", async () => {
  const fake = await Deno.readFile(new URL("fake.jpg", dir));
  assertEquals(sniff(fake), null);
  await assertRejects(() => sanitizeImage(fake), RejectedImage);
  // Valid JPEG header but truncated body
  const src = await Deno.readFile(new URL("gps.jpg", dir));
  await assertRejects(() => sanitizeImage(src.slice(0, 400)), RejectedImage);
});

Deno.test("media crypto: roundtrip, tamper, swapped id, rotation", async () => {
  const v1 = key(), v2 = key();
  Deno.env.set("MEDIA_KEKS", JSON.stringify({ v1 }));
  Deno.env.set("MEDIA_KEK_ACTIVE", "v1");
  resetKeyringForTests();
  const id = crypto.randomUUID();
  const plain = new TextEncoder().encode("pixels");
  const s = await sealMedia(id, plain);
  assert(!new TextDecoder().decode(s.ciphertext).includes("pixels"));
  const row = { wrapped_dek: s.wrappedDek, kek_id: s.kekId, nonce: s.nonce, sha256: s.sha256 };
  assertEquals(await openMedia(id, row, s.ciphertext), plain);

  const bad = s.ciphertext.slice(); bad[0] ^= 1;
  await assertRejects(() => openMedia(id, row, bad));
  await assertRejects(() => openMedia(crypto.randomUUID(), row, s.ciphertext)); // AAD binds the id

  Deno.env.set("MEDIA_KEKS", JSON.stringify({ v1, v2 }));
  Deno.env.set("MEDIA_KEK_ACTIVE", "v2");
  resetKeyringForTests();
  const next = (await rewrapDek(id, s.wrappedDek, "v1"))!;
  assertEquals(next.kekId, "v2");
  assertEquals(await openMedia(id, { ...row, wrapped_dek: next.wrappedDek, kek_id: "v2" }, s.ciphertext), plain);

  Deno.env.set("MEDIA_KEKS", JSON.stringify({ v2 }));  // v1 retired
  resetKeyringForTests();
  await assertRejects(() => openMedia(id, row, s.ciphertext));
});

Deno.test("moderation thresholds", () => {
  assertEquals(decide({ adult: "VERY_UNLIKELY", racy: "UNLIKELY", violence: "VERY_UNLIKELY" }), "approved");
  assertEquals(decide({ adult: "POSSIBLE" }), "pending");
  assertEquals(decide({ racy: "LIKELY" }), "pending");
  assertEquals(decide({ adult: "LIKELY" }), "rejected");
  assertEquals(decide({ racy: "VERY_LIKELY" }), "rejected");
  assertEquals(decide({}), "approved");
});

// ---------------------------------------------------------------- client WebP intake

function chunk(fourcc: string, data: Uint8Array) {
  const pad = data.length & 1;
  const out = new Uint8Array(8 + data.length + pad);
  out.set(new TextEncoder().encode(fourcc), 0);
  new DataView(out.buffer).setUint32(4, data.length, true);
  out.set(data, 8);
  return out;
}
function riff(chunks: Uint8Array[]) {
  const body = chunks.reduce((n, c) => n + c.length, 0);
  const out = new Uint8Array(12 + body);
  out.set(new TextEncoder().encode("RIFF"), 0);
  new DataView(out.buffer).setUint32(4, 4 + body, true);
  out.set(new TextEncoder().encode("WEBP"), 8);
  let o = 12;
  for (const c of chunks) { out.set(c, o); o += c.length; }
  return out;
}

Deno.test("image: keeps a client WebP's pixels but strips EXIF/XMP chunks", async () => {
  // Build a real 400x300 WebP, then wrap it in an extended file carrying metadata.
  await sanitizeImage(await Deno.readFile(new URL("gps.jpg", dir))); // initialises codecs
  const px = new ImageData(new Uint8ClampedArray(400 * 300 * 4).fill(180), 400, 300);
  const simple = new Uint8Array(await encodeWebp(px, { quality: 70 }));
  const vp8 = simple.subarray(12);
  const x = new Uint8Array(10);
  x[0] = 0x08 | 0x04; // EXIF + XMP flags
  x.set([(399) & 0xff, (399 >> 8) & 0xff, 0, (299) & 0xff, (299 >> 8) & 0xff, 0], 4);
  const tagged = riff([chunk("VP8X", x), vp8, chunk("EXIF", new TextEncoder().encode("SecretPhone 98765")),
                       chunk("XMP ", new TextEncoder().encode("<gps>9.93,76.26</gps>"))]);
  assertEquals(webpInfo(tagged), { w: 400, h: 300, animated: false });

  const out = await sanitizeImage(tagged);
  assertEquals([out.width, out.height], [400, 300]);
  const text = new TextDecoder("latin1").decode(out.webp);
  assert(!text.includes("SecretPhone") && !text.includes("gps") && !text.includes("EXIF"));
  assertEquals(out.webp[20] & (0x08 | 0x04), 0, "metadata flags cleared");
  assertEquals(stripWebp(stripWebp(tagged)), stripWebp(tagged));
});

Deno.test("image: rejects animated WebP and lies about dimensions", async () => {
  const x = new Uint8Array(10);
  x[0] = 0x02; // animation flag
  x.set([0x3f, 0x01, 0, 0x3f, 0x01, 0], 4);
  await assertRejects(() => sanitizeImage(riff([chunk("VP8X", x), chunk("ANIM", new Uint8Array(6))])), RejectedImage);
  await assertRejects(() => sanitizeImage(riff([chunk("VP8 ", new Uint8Array(30))])), RejectedImage);
});

Deno.test("image: oversize uploads are fitted into 1080 px with aspect kept", async () => {
  assertEquals(fitBox(4032, 3024), { w: 1080, h: 810 });
  assertEquals(fitBox(1080, 1920), { w: 608, h: 1080 });
  assertEquals(fitBox(800, 600), { w: 800, h: 600 });
  const src = await Deno.readFile(new URL("gps.jpg", dir));
  const out = await sanitizeImage(src);
  assert(Math.max(out.width, out.height) <= 1080 && out.webp.length <= 100 * 1024);
});

// ---------------------------------------------------------------- music connector
Deno.test("music: refresh tokens are sealed per user", async () => {
  Deno.env.set("MEDIA_KEKS", JSON.stringify({ v1: key() }));
  Deno.env.set("MEDIA_KEK_ACTIVE", "v1");
  resetKeyringForTests();
  const s = await sealSecret("music:user-a", "AQB-refresh-token");
  assert(!s.sealed.includes("refresh"));
  assertEquals(await openSecret("music:user-a", s.sealed, s.kekId), "AQB-refresh-token");
  await assertRejects(() => openSecret("music:user-b", s.sealed, s.kekId)); // bound to the user
});

Deno.test("music: artist mapping keeps id, name, medium image, genres", () => {
  const items = [
    { id: "4YRxDV8wJFPHPTeXepOstw", name: "Sushin Shyam", genres: ["malayalam indie", "filmi"],
      images: [{ url: "https://i.scdn.co/image/big", width: 640 }, { url: "https://i.scdn.co/image/mid", width: 320 },
               { url: "https://i.scdn.co/image/small", width: 160 }] },
    { id: "bad id", name: "x" },
    { id: "1mYsTxnqsietFxj1OgoGbG", name: "A. R. Rahman", images: [{ url: "http://evil.example/x.png", width: 320 }] },
  ];
  assertEquals(mapArtists(items), [
    { id: "4YRxDV8wJFPHPTeXepOstw", name: "Sushin Shyam", image: "https://i.scdn.co/image/mid", genres: ["malayalam indie", "filmi"] },
    { id: "1mYsTxnqsietFxj1OgoGbG", name: "A. R. Rahman", image: null, genres: [] },
  ]);
  assertEquals(mapArtists(undefined), []);
  assertEquals(pickImage([]), null);
});

function fakeFetch(handler: (url: string, init?: RequestInit) => Response): typeof fetch {
  return ((input: string | URL | Request, init?: RequestInit) => Promise.resolve(handler(String(input), init))) as typeof fetch;
}

Deno.test("music: OAuth requests stay server-side and handle edge cases", async () => {
  Deno.env.set("SPOTIFY_CLIENT_ID", "cid");
  Deno.env.set("SPOTIFY_CLIENT_SECRET", "csecret");
  Deno.env.set("SPOTIFY_REDIRECT_URI", "https://ref.supabase.co/functions/v1/music-callback");
  const url = new URL(authorizeUrl("s".repeat(43)));
  assertEquals(url.searchParams.get("scope"), "user-top-read user-read-recently-played");
  assert(!url.toString().includes("csecret"), "secret never in the browser URL");

  let sentBody = "";
  const ok = fakeFetch((u, init) => {
    if (u.endsWith("/api/token")) {
      sentBody = String(init?.body);
      assertEquals((init?.headers as Record<string, string>).Authorization, `Basic ${btoa("cid:csecret")}`);
      return Response.json({ access_token: "acc", refresh_token: "rot" });
    }
    assert(u.includes("/me/top/artists?limit=10&time_range=medium_term"));
    return Response.json({ items: [] });
  });
  assertEquals(await exchangeCode("code123", ok), { access: "acc", refresh: "rot", scope: null });
  assert(sentBody.includes("grant_type=authorization_code") && sentBody.includes("code=code123"));
  assertEquals(await refreshAccess("old", ok), { access: "acc", refresh: "rot", scope: null }, "rotated refresh token surfaced");
  assertEquals(await topArtists("acc", ok), [], "zero listening history is a valid, empty result");

  const revoked = fakeFetch(() => Response.json({ error: "invalid_grant" }, { status: 400 }));
  await assertRejects(() => refreshAccess("old", revoked), ReauthRequired);
  const limited = fakeFetch(() => new Response("", { status: 429, headers: { "Retry-After": "12" } }));
  const err = await assertRejects(() => topArtists("acc", limited), SpotifyRateLimited);
  assertEquals((err as SpotifyRateLimited).retryAfter, 12);
  const expired = fakeFetch(() => new Response("", { status: 401 }));
  await assertRejects(() => topArtists("acc", expired), ReauthRequired);
});

Deno.test("music: top tracks and recently played, with old grants and empty history", async () => {
  const album = { images: [{ url: "https://i.scdn.co/image/a640", width: 640 }, { url: "https://i.scdn.co/image/a300", width: 300 }] };
  assertEquals(mapTrack({ id: "3n3Ppam7vgaVa1iaRUc9Lp", name: "Song", artists: [{ name: "A" }, { name: "B" }], album }),
    { id: "3n3Ppam7vgaVa1iaRUc9Lp", name: "Song", artists: ["A", "B"], image: "https://i.scdn.co/image/a300" });
  assertEquals(mapTrack({ id: "x", name: "bad id" }), null);
  assertEquals(mapTrack({ id: "3n3Ppam7vgaVa1iaRUc9Lp", name: "No art", artists: [] })!.image, null);

  const played = { items: [{ played_at: "2026-11-09T10:00:00.000Z", track: { id: "3n3Ppam7vgaVa1iaRUc9Lp", name: "Song", artists: [], album } }] };
  const full = fakeFetch((u) =>
    u.includes("/recently-played") ? Response.json(played) : Response.json({ items: [] })
  );
  const r = await recentlyPlayed("acc", full);
  assertEquals(r[0].played_at, "2026-11-09T10:00:00.000Z");
  const all = await importAll("acc", full);
  assertEquals([all.artists.length, all.tracks.length, all.recent!.length], [0, 0, 1]);

  // Granted before the recently-played scope existed: Spotify answers 403.
  const oldGrant = fakeFetch((u) => u.includes("/recently-played") ? new Response("", { status: 403 }) : Response.json({ items: [] }));
  await assertRejects(() => recentlyPlayed("acc", oldGrant), ScopeMissing);
  assertEquals((await importAll("acc", oldGrant)).recent, null, "recently played is optional");

  const expired = fakeFetch(() => new Response("", { status: 401 }));
  await assertRejects(() => importAll("acc", expired), ReauthRequired);
});
