import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { RejectedImage, sanitizeImage, sniff } from "../image.ts";
import { openMedia, resetKeyringForTests, rewrapDek, sealMedia } from "../media_crypto.ts";
import { decide } from "../moderation.ts";

const dir = new URL(".", import.meta.url);
const key = () => btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))));

Deno.test("image: re-encodes to 800x800 WebP and strips EXIF/GPS", async () => {
  const src = await Deno.readFile(new URL("gps.jpg", dir));
  assert(new TextDecoder("latin1").decode(src).includes("SecretPhone"));
  const out = await sanitizeImage(src);
  assertEquals([out.width, out.height], [800, 800]);
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
