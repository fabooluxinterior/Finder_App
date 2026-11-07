// Pre-publication moderation with Google Cloud Vision SafeSearch.
// Runs on the sanitised image before it is encrypted and attached to a
// profile. Without GOOGLE_VISION_API_KEY every image waits for manual review.
export type Verdict = { status: "approved" | "pending" | "rejected"; labels: Record<string, string> };

const rank: Record<string, number> = { UNKNOWN: 0, VERY_UNLIKELY: 1, UNLIKELY: 2, POSSIBLE: 3, LIKELY: 4, VERY_LIKELY: 5 };

export function decide(s: Record<string, string>): Verdict["status"] {
  const r = (k: string) => rank[s[k] ?? "UNKNOWN"] ?? 0;
  if (r("adult") >= 4 || r("violence") >= 5 || r("racy") >= 5) return "rejected";
  if (r("adult") >= 3 || r("racy") >= 4 || r("violence") >= 4 || r("medical") >= 5) return "pending";
  return "approved";
}

export async function moderate(image: Uint8Array): Promise<Verdict> {
  const key = Deno.env.get("GOOGLE_VISION_API_KEY");
  if (!key) return { status: "pending", labels: { provider: "none" } };
  let content = "";
  for (let i = 0; i < image.length; i += 0x8000) content += String.fromCharCode(...image.subarray(i, i + 0x8000));
  const res = await fetch("https://vision.googleapis.com/v1/images:annotate", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Goog-Api-Key": key },
    body: JSON.stringify({ requests: [{ image: { content: btoa(content) }, features: [{ type: "SAFE_SEARCH_DETECTION" }] }] }),
  });
  if (!res.ok) return { status: "pending", labels: { provider_error: String(res.status) } };
  const body = await res.json();
  const labels = body?.responses?.[0]?.safeSearchAnnotation ?? {};
  return { status: decide(labels), labels };
}
