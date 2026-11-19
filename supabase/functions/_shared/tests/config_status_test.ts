import { assert, assertEquals } from "jsr:@std/assert@1";
import { presence, SERVICES, validate } from "../config_status.ts";

const SECRET = "sk_live_super_secret_value_1234567890";
const full: Record<string, string> = {
  SUPABASE_URL: "https://x.supabase.co", SUPABASE_ANON_KEY: "anon", SUPABASE_SERVICE_ROLE_KEY: SECRET,
  MEDIA_KEKS: SECRET, MEDIA_KEK_ACTIVE: "k1", SPOTIFY_CLIENT_ID: "3315a3d3e8c349689a8c5f00dad3cc2e",
  SPOTIFY_CLIENT_SECRET: SECRET, SPOTIFY_REDIRECT_URI: "https://x.supabase.co/functions/v1/music-callback",
  REVENUECAT_WEBHOOK_AUTH: SECRET, GOOGLE_VISION_API_KEY: SECRET, ALLOWED_ORIGINS: "https://admin.example.com",
};

Deno.test("config status: reports missing names, never values", () => {
  const env = (k: string) => (k === "SPOTIFY_CLIENT_SECRET" ? undefined : full[k]);
  const p = presence(env);
  assertEquals(p.length, SERVICES.length);
  const spotify = p.find((s) => s.service === "spotify")!;
  assertEquals(spotify.configured, false);
  assertEquals(spotify.missing, ["SPOTIFY_CLIENT_SECRET"]);
  assert(!JSON.stringify(p).includes(SECRET), "no secret in the report");
  assert(!JSON.stringify(p).includes("3315a3d3"), "no values at all");
});

Deno.test("config status: validation is live and leak-free", async () => {
  const env = (k: string) => full[k];
  let sent = "";
  const ok = await validate("spotify", env, {
    fetch: async (_u, init) => { sent = String(init?.body); return new Response("{}", { status: 200 }); },
  });
  assertEquals(ok.valid, true);
  assertEquals(sent, "grant_type=client_credentials");
  const bad = await validate("spotify", env, { fetch: async () => new Response("{}", { status: 400 }) });
  assertEquals(bad.valid, false);
  assert(!JSON.stringify([ok, bad]).includes(SECRET));
  assertEquals((await validate("media_keys", env, { mediaRoundtrip: async () => true })).valid, true);
  assertEquals((await validate("media_keys", env, { mediaRoundtrip: async () => false })).valid, false);
  assertEquals((await validate("revenuecat", (k) => (k === "REVENUECAT_WEBHOOK_AUTH" ? "short" : full[k]))).valid, false);
  assertEquals((await validate("cors", (k) => (k === "ALLOWED_ORIGINS" ? "http://insecure.example" : full[k]))).valid, false);
  const missing = await validate("spotify", () => undefined);
  assertEquals(missing.valid, false);
  assert(missing.message.includes("SPOTIFY_CLIENT_ID"));
});
