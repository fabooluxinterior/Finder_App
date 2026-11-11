// Pre-publication moderation. Runs on the sanitised image before it is
// encrypted and attached to a profile. Providers (first one configured wins,
// or force one with MODERATION_PROVIDER=openai|google):
//   * OpenAI Moderation (OPENAI_API_KEY)  - free to use, images supported
//   * Google Cloud Vision (GOOGLE_VISION_API_KEY) - SafeSearch
// With neither key set, or when the provider is down, every image waits for
// manual review (never auto-approved, never lost). Secrets never reach a
// response, a label or a log line.
export type Verdict = { status: "approved" | "pending" | "rejected"; labels: Record<string, string> };

const rank: Record<string, number> = { UNKNOWN: 0, VERY_UNLIKELY: 1, UNLIKELY: 2, POSSIBLE: 3, LIKELY: 4, VERY_LIKELY: 5 };

/** Google SafeSearch likelihoods -> verdict. */
export function decide(s: Record<string, string>): Verdict["status"] {
  const r = (k: string) => rank[s[k] ?? "UNKNOWN"] ?? 0;
  if (r("adult") >= 4 || r("violence") >= 5 || r("racy") >= 5) return "rejected";
  if (r("adult") >= 3 || r("racy") >= 4 || r("violence") >= 4 || r("medical") >= 5) return "pending";
  return "approved";
}

/**
 * OpenAI moderation scores (0..1) -> verdict. Conservative: anything OpenAI
 * itself flags, or scores above our own lower bars, goes to a person; only
 * clearly explicit/graphic images are rejected outright. Ordinary swimwear and
 * shirtless photos score low on "sexual" and pass.
 */
export function decideOpenAI(scores: Record<string, number>, flagged: Record<string, boolean> = {}): Verdict["status"] {
  const s = (k: string) => scores[k] ?? 0;
  if (s("sexual/minors") >= 0.4 || s("sexual") >= 0.8 || s("violence/graphic") >= 0.8) return "rejected";
  if (
    s("sexual/minors") >= 0.05 || s("sexual") >= 0.3 || s("violence/graphic") >= 0.3 || s("violence") >= 0.6 ||
    s("self-harm") >= 0.5 || s("hate") >= 0.7 ||
    flagged["sexual"] || flagged["sexual/minors"] || flagged["violence/graphic"] || flagged["violence"] || flagged["self-harm"]
  ) return "pending";
  return "approved";
}

export type Env = (name: string) => string | undefined;

function base64(image: Uint8Array): string {
  let content = "";
  for (let i = 0; i < image.length; i += 0x8000) content += String.fromCharCode(...image.subarray(i, i + 0x8000));
  return btoa(content);
}

async function openAI(image: Uint8Array, key: string, f: typeof fetch): Promise<Verdict> {
  const res = await f("https://api.openai.com/v1/moderations", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: "omni-moderation-latest",
      input: [{ type: "image_url", image_url: { url: `data:image/webp;base64,${base64(image)}` } }],
    }),
    signal: AbortSignal.timeout(10_000),
  });
  if (!res.ok) {
    await res.body?.cancel();
    return { status: "pending", labels: { provider: "openai", provider_error: String(res.status) } };
  }
  const r = (await res.json())?.results?.[0];
  if (!r || typeof r.category_scores !== "object") {
    return { status: "pending", labels: { provider: "openai", provider_error: "bad_response" } };
  }
  const scores = r.category_scores as Record<string, number>;
  const status = decideOpenAI(scores, (r.categories ?? {}) as Record<string, boolean>);
  const labels: Record<string, string> = { provider: "openai" };
  for (const k of ["sexual", "sexual/minors", "violence", "violence/graphic", "self-harm", "hate"]) {
    if (typeof scores[k] === "number") labels[k] = scores[k].toFixed(3);
  }
  return { status, labels };
}

async function googleVision(image: Uint8Array, key: string, f: typeof fetch): Promise<Verdict> {
  const res = await f("https://vision.googleapis.com/v1/images:annotate", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Goog-Api-Key": key },
    body: JSON.stringify({ requests: [{ image: { content: base64(image) }, features: [{ type: "SAFE_SEARCH_DETECTION" }] }] }),
    signal: AbortSignal.timeout(10_000),
  });
  if (!res.ok) {
    await res.body?.cancel();
    return { status: "pending", labels: { provider: "google", provider_error: String(res.status) } };
  }
  const body = await res.json();
  const labels = body?.responses?.[0]?.safeSearchAnnotation ?? {};
  return { status: decide(labels), labels: { provider: "google", ...labels } };
}

export async function moderate(
  image: Uint8Array,
  env: Env = (k) => Deno.env.get(k),
  f: typeof fetch = fetch,
): Promise<Verdict> {
  const openaiKey = (env("OPENAI_API_KEY") ?? "").trim();
  const googleKey = (env("GOOGLE_VISION_API_KEY") ?? "").trim();
  const forced = (env("MODERATION_PROVIDER") ?? "").trim().toLowerCase();
  const provider = forced === "openai" && openaiKey
    ? "openai"
    : forced === "google" && googleKey
    ? "google"
    : openaiKey
    ? "openai"
    : googleKey
    ? "google"
    : "none";
  if (provider === "none") return { status: "pending", labels: { provider: "none" } };
  try {
    return provider === "openai" ? await openAI(image, openaiKey, f) : await googleVision(image, googleKey, f);
  } catch (_) {
    // Network error or timeout: a person reviews it instead of the upload failing.
    return { status: "pending", labels: { provider, provider_error: "unreachable" } };
  }
}
