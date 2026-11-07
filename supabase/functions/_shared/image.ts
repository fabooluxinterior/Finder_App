// Server-side image validation and sanitisation.
// The uploaded bytes are never stored or served: we sniff the real format
// from magic bytes, fully decode to pixels, bound the dimensions, and encode
// a brand-new WebP. That drops EXIF/GPS/XMP and any embedded payload.
import decodeJpeg, { init as initJpeg } from "npm:@jsquash/jpeg@1.6.0/decode.js";
import decodePng, { init as initPng } from "npm:@jsquash/png@3.1.1/decode.js";
import encodeWebp, { init as initWebp } from "npm:@jsquash/webp@1.5.0/encode.js";
import resize, { initResize } from "npm:@jsquash/resize@2.1.1";

let ready: Promise<void> | null = null;
function initCodecs() {
  const load = (f: string) => Deno.readFile(new URL(`./wasm/${f}`, import.meta.url)).then((b) => WebAssembly.compile(b));
  ready ??= (async () => {
    const [jpeg, png, webp, rs] = await Promise.all([
      load("mozjpeg_dec.wasm"), load("squoosh_png_bg.wasm"), load("webp_enc_simd.wasm"), load("squoosh_resize_bg.wasm"),
    ]);
    await Promise.all([initJpeg(jpeg), initPng(png), initWebp(webp), initResize(rs)]);
  })();
  return ready;
}

export const MAX_UPLOAD_BYTES = 8 * 1024 * 1024;
const MAX_PIXELS = 40_000_000; // decompression-bomb guard
const OUT_SIDE = 800;
const OUT_MAX_BYTES = 100 * 1024;

export type Sniffed = "jpeg" | "png";

export function sniff(b: Uint8Array): Sniffed | null {
  if (b.length > 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "jpeg";
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

export class RejectedImage extends Error {}

export async function sanitizeImage(bytes: Uint8Array): Promise<{ webp: Uint8Array; width: number; height: number }> {
  if (bytes.length === 0 || bytes.length > MAX_UPLOAD_BYTES) throw new RejectedImage("File is empty or too large.");
  const kind = sniff(bytes);
  if (!kind) throw new RejectedImage("Only JPEG and PNG photos are accepted.");
  const dims = kind === "png" ? pngDimensions(bytes) : jpegDimensions(bytes);
  if (!dims || dims.w < 200 || dims.h < 200 || dims.w * dims.h > MAX_PIXELS) {
    throw new RejectedImage("Photo dimensions are not supported (min 200×200).");
  }

  await initCodecs();
  let img: ImageData;
  try {
    const buf = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
    img = kind === "png" ? await decodePng(buf) : await decodeJpeg(buf);
  } catch {
    throw new RejectedImage("The file could not be read as an image.");
  }
  if (img.width !== dims.w || img.height !== dims.h) throw new RejectedImage("The file could not be read as an image.");

  // Centre-crop to a square (copying pixels only), then scale to 800×800.
  const side = Math.min(img.width, img.height);
  const x0 = Math.floor((img.width - side) / 2), y0 = Math.floor((img.height - side) / 2);
  const sq = new Uint8ClampedArray(side * side * 4);
  for (let y = 0; y < side; y++) {
    const from = ((y + y0) * img.width + x0) * 4;
    sq.set(img.data.subarray(from, from + side * 4), y * side * 4);
  }
  let out = new ImageData(sq, side, side);
  if (side > OUT_SIDE) out = await resize(out, { width: OUT_SIDE, height: OUT_SIDE, method: "lanczos3" });

  for (let q = 70; q >= 30; q -= 10) {
    const webp = new Uint8Array(await encodeWebp(out, { quality: q }));
    if (webp.length <= OUT_MAX_BYTES) return { webp, width: out.width, height: out.height };
  }
  throw new RejectedImage("Photo is too detailed to optimise. Try another one.");
}
