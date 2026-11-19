// Envelope encryption for stored media using WebCrypto AES-256-GCM.
//   * Each object gets a fresh random 256-bit data key (DEK).
//   * The DEK is wrapped (AES-256-GCM) with a key-encryption key (KEK) from
//     the keyring in MEDIA_KEKS, and only the wrapped DEK is stored in the DB.
//   * AAD binds ciphertexts to the media id and key version, so objects
//     can't be swapped between rows.
// KEKs live only in the function's secret store (Supabase secrets, or a KMS
// that injects them), never in the database or the client.
const enc = new TextEncoder();
// Copy into a plain ArrayBuffer-backed view (WebCrypto's BufferSource type).
const buf = (u: Uint8Array): Uint8Array<ArrayBuffer> => new Uint8Array(u);
const b64 = (u: Uint8Array) => btoa(String.fromCharCode(...u));
const unb64 = (s: string) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

type Keyring = { active: string; keys: Map<string, CryptoKey> };
let ring: Promise<Keyring> | null = null;

async function keyring(): Promise<Keyring> {
  ring ??= (async () => {
    const raw = JSON.parse(Deno.env.get("MEDIA_KEKS") ?? "{}") as Record<string, string>;
    const active = Deno.env.get("MEDIA_KEK_ACTIVE") ?? "";
    const keys = new Map<string, CryptoKey>();
    for (const [id, k] of Object.entries(raw)) {
      const bytes = unb64(k);
      if (bytes.length !== 32) throw new Error(`KEK ${id} must be 32 bytes`);
      keys.set(id, await crypto.subtle.importKey("raw", buf(bytes), "AES-GCM", false, ["encrypt", "decrypt"]));
    }
    if (!keys.has(active)) throw new Error("MEDIA_KEK_ACTIVE is not in MEDIA_KEKS");
    return { active, keys };
  })();
  return ring;
}

async function gcm(op: "encrypt" | "decrypt", key: CryptoKey, iv: Uint8Array, data: Uint8Array, aad: string) {
  const params = { name: "AES-GCM", iv: buf(iv), additionalData: enc.encode(aad), tagLength: 128 };
  return new Uint8Array(await crypto.subtle[op](params, key, buf(data)));
}

export type Sealed = { ciphertext: Uint8Array; wrappedDek: string; kekId: string; nonce: string; sha256: string };

export async function sealMedia(mediaId: string, plaintext: Uint8Array): Promise<Sealed> {
  const { active, keys } = await keyring();
  const dekBytes = crypto.getRandomValues(new Uint8Array(32));
  const dek = await crypto.subtle.importKey("raw", buf(dekBytes), "AES-GCM", false, ["encrypt"]);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await gcm("encrypt", dek, iv, plaintext, `media:${mediaId}`);

  const wrapIv = crypto.getRandomValues(new Uint8Array(12));
  const wrapped = await gcm("encrypt", keys.get(active)!, wrapIv, dekBytes, `dek:${mediaId}:${active}`);
  dekBytes.fill(0);
  const sha = new Uint8Array(await crypto.subtle.digest("SHA-256", buf(ciphertext)));
  return { ciphertext, wrappedDek: `${b64(wrapIv)}.${b64(wrapped)}`, kekId: active, nonce: b64(iv), sha256: b64(sha) };
}

async function unwrapDek(mediaId: string, wrappedDek: string, kekId: string): Promise<Uint8Array> {
  const { keys } = await keyring();
  const kek = keys.get(kekId);
  if (!kek) throw new Error("unknown KEK version");
  const [iv, ct] = wrappedDek.split(".");
  return gcm("decrypt", kek, unb64(iv), unb64(ct), `dek:${mediaId}:${kekId}`);
}

export async function openMedia(mediaId: string, row: { wrapped_dek: string; kek_id: string; nonce: string; sha256: string }, ciphertext: Uint8Array) {
  const sha = new Uint8Array(await crypto.subtle.digest("SHA-256", buf(ciphertext)));
  if (b64(sha) !== row.sha256) throw new Error("integrity check failed");
  const dekBytes = await unwrapDek(mediaId, row.wrapped_dek, row.kek_id);
  const dek = await crypto.subtle.importKey("raw", buf(dekBytes), "AES-GCM", false, ["decrypt"]);
  dekBytes.fill(0);
  return gcm("decrypt", dek, unb64(row.nonce), ciphertext, `media:${mediaId}`);
}

/** Key rotation: re-wrap a DEK under the active KEK (object bytes unchanged). */
export async function rewrapDek(mediaId: string, wrappedDek: string, kekId: string) {
  const { active, keys } = await keyring();
  if (kekId === active) return null;
  const dekBytes = await unwrapDek(mediaId, wrappedDek, kekId);
  const wrapIv = crypto.getRandomValues(new Uint8Array(12));
  const wrapped = await gcm("encrypt", keys.get(active)!, wrapIv, dekBytes, `dek:${mediaId}:${active}`);
  dekBytes.fill(0);
  return { wrappedDek: `${b64(wrapIv)}.${b64(wrapped)}`, kekId: active };
}

/** Small secrets (e.g. OAuth refresh tokens): AES-256-GCM directly under the
 *  active KEK, AAD-bound to a context string such as `music:<user id>`. */
export async function sealSecret(context: string, plaintext: string): Promise<{ sealed: string; kekId: string }> {
  const { active, keys } = await keyring();
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = await gcm("encrypt", keys.get(active)!, iv, enc.encode(plaintext), `secret:${context}:${active}`);
  return { sealed: `${b64(iv)}.${b64(ct)}`, kekId: active };
}

export async function openSecret(context: string, sealed: string, kekId: string): Promise<string> {
  const { keys } = await keyring();
  const kek = keys.get(kekId);
  if (!kek) throw new Error("unknown KEK version");
  const [iv, ct] = sealed.split(".");
  return new TextDecoder().decode(await gcm("decrypt", kek, unb64(iv), unb64(ct), `secret:${context}:${kekId}`));
}

export function resetKeyringForTests() {
  ring = null;
}
