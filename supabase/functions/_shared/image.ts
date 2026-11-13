// Server-side image validation and sanitisation.
// The app already shrinks photos to a ≤1080 px, ≤100 KB WebP before upload
// (lib/core/image_optimizer.dart), so most uploads arrive ready to store. The
// server still never trusts them: it sniffs the real format from magic bytes,
// fully decodes the pixels, and only keeps files that are well-formed.
//   * Client WebP within limits: metadata chunks (EXIF/XMP/ICC) are removed
//     from the RIFF container without re-encoding (no generation loss).
//   * Anything else (JPEG/PNG from older clients, oversize WebP): decoded and
//     encoded as a brand-new WebP, which drops all metadata and payloads.
import decodeJpeg, { init as initJpeg } from "npm:@jsquash/jpeg@1.6.0/decode.js";
import decodePng, { init as initPng } from "npm:@jsquash/png@3.1.1/decode.js";
import decodeWebp, { init as initWebpDec } from "npm:@jsquash/webp@1.5.0/decode.js";
import encodeWebp, { init as initWebp } from "npm:@jsquash/webp@1.5.0/encode.js";
import resize, { initResize } from "npm:@jsquash/resize@2.1.1";

let ready: Promise<void> | null = null;
function initCodecs() {
  const load = (f: string) => Deno.readFile(new URL(`./wasm/${f}`, import.meta.url)).then((b) => WebAssembly.compile(b));
  ready ??= (async () => {
    const [jpeg, png, webpDec, webp, rs] = await Promise.all([
      load("mozjpeg_dec.wasm"), load("squoosh_png_bg.wasm"), load("webp_dec.wasm"), load("webp_enc_simd.wasm"),
      load("squoosh_resize_bg.wasm"),
    ]);
    await Promise.all([initJpeg(jpeg), initPng(png), initWebpDec(webpDec), initWebp(webp), initResize(rs)]);
  })();
  return ready;
}

export const MAX_UPLOAD_BYTES = 8 * 1024 * 1024;
const MAX_PIXELS = 40_000_000; // decompression-bomb guard
export const OUT_SIDE = 1080;
export const OUT_MAX_BYTES = 100 * 1024;
const MIN_SIDE = 200;

export type Sniffed = "jpeg" | "png" | "webp";

const ascii = (b: Uint8Array, at: number, n: number) => String.fromCharCode(...b.subarray(at, at + n));

export function sniff(b: Uint8Array): Sniffed | null {
  if (b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "jpeg";
  if (b.length > 16 && ascii(b, 0, 4) === "RIFF" && ascii(b, 8, 4) === "WEBP") return "webp";
  if (b.length > 8 && [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every((v, i) => b[i] === v)) return "png";
  return null;
}

function pngDimensions(b: Uint8Array) {
  const v = new DataView(b.buffer, b.byteOffset, b.byteLength);
  return { w: v.getUint32(16), h: v.getUint32(20) };
}

function jpegDimensions(b: Uint8Array) {
  let i = 2;
  while (i + 9 < b.length) {
    if (b[i] !== 0xff) return null;
    const marker = b[i + 1];
    const len = (b[i + 2] << 8) | b[i + 3];
    if (marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker)) {
      return { h: (b[i + 5] << 8) | b[i + 6], w: (b[i + 7] << 8) | b[i + 8] };
    }
    i += 2 + len;
  }
  return null;
}

type Chunk = { fourcc: string; start: number; end: number };

/** Walks the RIFF container. Throws on malformed sizes. */
export function webpChunks(b: Uint8Array): Chunk[] {
  const v = new DataView(b.buffer, b.byteOffset, b.byteLength);
  const riffEnd = 8 + v.getUint32(4, true);
  if (riffEnd > b.length || riffEnd < 20) throw new RejectedImage("The file could not be read as an image.");
  const out: Chunk[] = [];
  let i = 12;
  while (i + 8 <= riffEnd) {
    const size = v.getUint32(i + 4, true);
    const end = i + 8 + size + (size & 1);
    if (end > riffEnd) throw new RejectedImage("The file could not be read as an image.");
    out.push({ fourcc: ascii(b, i, 4), start: i, end });
    i = end;
  }
  if (i !== riffEnd) throw new RejectedImage("The file could not be read as an image.");
  return out;
}

export function webpInfo(b: Uint8Array): { w: number; h: number; animated: boolean } | null {
  const chunks = webpChunks(b);
  const first = chunks[0];
  if (!first) return null;
  const d = first.start + 8;
  if (first.fourcc === "VP8X") {
    const flags = b[d];
    const w = 1 + (b[d + 4] | (b[d + 5] << 8) | (b[d + 6] << 16));
    const h = 1 + (b[d + 7] | (b[d + 8] << 8) | (b[d + 9] << 16));
    return { w, h, animated: (flags & 0x02) !== 0 || chunks.some((c) => c.fourcc === "ANIM" || c.fourcc === "ANMF") };
  }
  if (first.fourcc === "VP8 ") {
    // keyframe start code 9d 01 2a, then 14-bit width/height
    if (b[d + 3] !== 0x9d || b[d + 4] !== 0x01 || b[d + 5] !== 0x2a) return null;
    return { w: (b[d + 6] | (b[d + 7] << 8)) & 0x3fff, h: (b[d + 8] | (b[d + 9] << 8)) & 0x3fff, animated: false };
  }
  if (first.fourcc === "VP8L") {
    if (b[d] !== 0x2f) return null;
    const bits = b[d + 1] | (b[d + 2] << 8) | (b[d + 3] << 16) | (b[d + 4] << 24);
    return { w: (bits & 0x3fff) + 1, h: ((bits >>> 14) & 0x3fff) + 1, animated: false };
  }
  return null;
}

/** Rebuilds a still WebP keeping only image chunks (VP8X with metadata
 *  flags cleared, ALPH, VP8, VP8L). EXIF, XMP, ICC and unknown chunks go. */
export function stripWebp(b: Uint8Array): Uint8Array {
  const keep = webpChunks(b).filter((c) => ["VP8X", "ALPH", "VP8 ", "VP8L"].includes(c.fourcc));
  const body = new Uint8Array(keep.reduce((n, c) => n + (c.end - c.start), 0));
  let o = 0;
  for (const c of keep) {
    body.set(b.subarray(c.start, c.end), o);
    if (c.fourcc === "VP8X") body[o + 8] &= ~(0x20 | 0x08 | 0x04); // ICC, EXIF, XMP flags
    o += c.end - c.start;
  }
  const out = new Uint8Array(12 + body.length);
  out.set([0x52, 0x49, 0x46, 0x46], 0);
  new DataView(out.buffer).setUint32(4, 4 + body.length, true);
  out.set([0x57, 0x45, 0x42, 0x50], 8);
  out.set(body, 12);
  return out;
}

export class RejectedImage extends Error {}

/** Largest size inside the 1080 px box with the same aspect ratio. */
export function fitBox(w: number, h: number, side = OUT_SIDE) {
  const s = Math.min(1, side / Math.max(w, h));
  return { w: Math.max(1, Math.round(w * s)), h: Math.max(1, Math.round(h * s)) };
}

export async function sanitizeImage(bytes: Uint8Array): Promise<{ webp: Uint8Array; width: number; height: number }> {
  if (bytes.length === 0 || bytes.length > MAX_UPLOAD_BYTES) throw new RejectedImage("File is empty or too large.");
  const kind = sniff(bytes);
  if (!kind) throw new RejectedImage("Only JPEG, PNG and WebP photos are accepted.");
  const dims = kind === "png" ? pngDimensions(bytes)
    : kind === "jpeg" ? jpegDimensions(bytes)
    : webpInfo(bytes);
  if (!dims || dims.w < MIN_SIDE || dims.h < MIN_SIDE || dims.w * dims.h > MAX_PIXELS) {
    throw new RejectedImage("Photo dimensions are not supported (min 200×200).");
  }
  if ("animated" in dims && dims.animated) throw new RejectedImage("Animated images aren't supported.");

  await initCodecs();
  let img: ImageData;
  try {
    const buf = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
    img = kind === "png" ? await decodePng(buf) : kind === "jpeg" ? await decodeJpeg(buf) : await decodeWebp(buf);
  } catch {
    throw new RejectedImage("The file could not be read as an image.");
  }
  if (img.width !== dims.w || img.height !== dims.h) throw new RejectedImage("The file could not be read as an image.");

  // Already optimised on the device: keep the pixels, drop the metadata.
  if (kind === "webp" && Math.max(img.width, img.height) <= OUT_SIDE) {
    const stripped = stripWebp(bytes);
    if (stripped.length <= OUT_MAX_BYTES) return { webp: stripped, width: img.width, height: img.height };
  }

  // Otherwise re-encode inside the 1080 px box (aspect ratio kept), lowering
  // quality and then size until it fits under 100 KB.
  let target = fitBox(img.width, img.height);
  for (let attempt = 0; attempt < 4; attempt++) {
    const out = target.w === img.width && target.h === img.height
      ? img
      : await resize(img, { width: target.w, height: target.h, method: "lanczos3" });
    for (let q = 78; q >= 38; q -= 8) {
      const webp = new Uint8Array(await encodeWebp(out, { quality: q }));
      if (webp.length <= OUT_MAX_BYTES) return { webp, width: out.width, height: out.height };
    }
    target = { w: Math.round(target.w * 0.85), h: Math.round(target.h * 0.85) };
    if (Math.min(target.w, target.h) < MIN_SIDE) break;
  }
  throw new RejectedImage("Photo is too detailed to optimise. Try another one.");
}
