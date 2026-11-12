// Firebase Cloud Messaging (HTTP v1) from an edge function. The service-account key lives only in the
// FCM_SERVICE_ACCOUNT secret; it is never logged or returned.

export interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

/** Pasting often adds quote marks or escapes around the JSON; undo that so a correct key still works. */
function unwrap(raw: string): string {
  let v = raw.trim();
  for (let i = 0; i < 2; i++) {
    if (v.startsWith("{")) return v;
    if (v.length > 1 && v.startsWith('"') && v.endsWith('"')) {
      const inner = v.slice(1, -1).trim();
      if (inner.startsWith("{")) {
        // either a JSON-encoded string ("{\"type\":...}") or the plain JSON in quotes
        try {
          const decoded = JSON.parse(v);
          if (typeof decoded === "string") { v = decoded.trim(); continue; }
        } catch { /* plain JSON in quotes */ }
        return inner;
      }
    }
    break;
  }
  // The outer { } were left out when copying: the text starts at "type": and ends with a quote.
  if (v.startsWith('"') && v.includes('"private_key"') && !v.startsWith('"{')) return `{${v}}`;
  return v;
}

/** Parses the secret; null when it is missing or incomplete (reported as "Not configured"). */
export function parseServiceAccount(raw: string | undefined | null): ServiceAccount | null {
  if (!raw) return null;
  try {
    const j = JSON.parse(unwrap(raw));
    if (typeof j.project_id === "string" && typeof j.client_email === "string" && typeof j.private_key === "string") {
      return { project_id: j.project_id, client_email: j.client_email, private_key: j.private_key };
    }
  } catch { /* fall through */ }
  return null;
}

/** Why the secret can't be used, without ever revealing it ("" when it is fine). */
export function diagnoseServiceAccount(raw: string | undefined | null): string {
  if (!raw) return "FCM_SERVICE_ACCOUNT is not set.";
  let j: Record<string, unknown>;
  try {
    j = JSON.parse(unwrap(raw));
  } catch {
    // Only the first and last three characters (punctuation/whitespace in a JSON file), to show the shape.
    const u = unwrap(raw);
    return `The value is not valid JSON (length ${raw.length}; after removing quotes it starts ${JSON.stringify(u.slice(0, 3))} and ends ${JSON.stringify(u.slice(-3))}). Paste the whole file, from { to }.`;
  }
  if (typeof j !== "object" || j === null) return "The value is JSON but not an object.";
  const missing = ["project_id", "client_email", "private_key"].filter((k) => typeof j[k] !== "string");
  if (missing.length) return `The JSON is missing: ${missing.join(", ")}.`;
  return "";
}

const b64url = (data: Uint8Array | string): string => {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
};

function pemToDer(pem: string): Uint8Array<ArrayBuffer> {
  const body = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0)) as Uint8Array<ArrayBuffer>;
}

/** The signed JWT Google exchanges for an access token (RS256). */
export async function signServiceJwt(sa: ServiceAccount, nowSeconds = Math.floor(Date.now() / 1000)): Promise<string> {
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  }));
  const key = await crypto.subtle.importKey("pkcs8", pemToDer(sa.private_key), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`)));
  return `${header}.${claims}.${b64url(sig)}`;
}

export async function fcmAccessToken(sa: ServiceAccount): Promise<string> {
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: await signServiceJwt(sa) }),
  });
  if (!res.ok) {
    // Google's error code only (never the key or token) so a bad setup can be diagnosed from the logs.
    const detail = await res.json().then((j) => String(j.error_description ?? j.error ?? "")).catch(() => "");
    throw new Error(`fcm_auth_${res.status} ${detail}`.trim());
  }
  return (await res.json()).access_token as string;
}

export interface MessageExtras {
  kind?: string; // "announcement" (dashboard) or "message" (chat)
  tag?: string; // same tag replaces the earlier notification (one per chat)
}

export function buildMessage(token: string, title: string, body: string, extras: MessageExtras = {}) {
  return {
    message: {
      token,
      notification: { title, body },
      data: { kind: extras.kind ?? "announcement" },
      android: {
        priority: "HIGH",
        notification: {
          // High-importance channels (created by the app) make the banner slide in from the top.
          channel_id: extras.kind === "message" ? "messages" : "announcements",
          icon: "ic_notification",
          color: "#FF5A3D",
          default_sound: true,
          notification_priority: "PRIORITY_HIGH",
          ...(extras.tag ? { tag: extras.tag } : {}),
        },
      },
    },
  };
}

export type SendResult = "ok" | "unregistered" | "failed";

export async function sendFcm(
  sa: ServiceAccount,
  accessToken: string,
  token: string,
  title: string,
  body: string,
  extras: MessageExtras = {},
): Promise<SendResult> {
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
    body: JSON.stringify(buildMessage(token, title, body, extras)),
  });
  if (res.ok) return "ok";
  // 404 UNREGISTERED / 400 INVALID_ARGUMENT for a dead token: remove it.
  if (res.status === 404 || res.status === 400) {
    await res.body?.cancel();
    return "unregistered";
  }
  await res.body?.cancel();
  return "failed";
}
