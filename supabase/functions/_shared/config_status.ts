// Which server-side settings each integration needs, and safe live checks.
// Reports only "configured / missing / valid" — never a value, a prefix or a
// length. Used by the admin-config-status function (admin web app).

export interface ServiceSpec {
  service: string;
  label: string;
  /** Needed for the app to work at all (vs. optional features). */
  required: boolean;
  vars: string[];
  /** Variables that are nice to have but not needed. */
  optionalVars?: string[];
  setup: string;
}

export const SERVICES: ServiceSpec[] = [
  {
    service: "supabase",
    label: "Supabase (service access)",
    required: true,
    vars: ["SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY"],
    setup: "Provided automatically to edge functions by Supabase.",
  },
  {
    service: "media_keys",
    label: "Photo encryption keys",
    required: true,
    vars: ["MEDIA_KEKS", "MEDIA_KEK_ACTIVE"],
    setup:
      "supabase secrets set MEDIA_KEKS=... MEDIA_KEK_ACTIVE=... (see .env.example). Add a new key version; never replace or delete an existing one.",
  },
  {
    service: "spotify",
    label: "Spotify",
    required: false,
    vars: ["SPOTIFY_CLIENT_ID", "SPOTIFY_CLIENT_SECRET", "SPOTIFY_REDIRECT_URI"],
    optionalVars: ["MUSIC_RETURN_URL"],
    setup:
      "Spotify dashboard → your app → Basic Information; then supabase secrets set SPOTIFY_CLIENT_ID=... SPOTIFY_CLIENT_SECRET=... SPOTIFY_REDIRECT_URI=https://<ref>.supabase.co/functions/v1/music-callback",
  },
  {
    service: "revenuecat",
    label: "RevenueCat webhook (Fast-Track)",
    required: false,
    vars: ["REVENUECAT_WEBHOOK_AUTH"],
    setup:
      "Generate a long random string; set it in RevenueCat (webhook Authorization) and with supabase secrets set REVENUECAT_WEBHOOK_AUTH=...",
  },
  {
    service: "moderation",
    label: "Image moderation (OpenAI, recommended)",
    required: false,
    vars: ["OPENAI_API_KEY"],
    setup:
      "Create an OpenAI API key (platform.openai.com); set OPENAI_API_KEY in Supabase → Edge Functions → Secrets. Without any moderation key every photo waits for manual review.",
  },
  {
    service: "moderation_google",
    label: "Image moderation (Google Vision, alternative)",
    required: false,
    vars: ["GOOGLE_VISION_API_KEY"],
    setup:
      "Google Cloud → Vision API key restricted to the Vision API; set GOOGLE_VISION_API_KEY in Supabase secrets. Used only when no OpenAI key is set (or MODERATION_PROVIDER=google).",
  },
  {
    service: "support_email",
    label: "Support ticket emails",
    required: false,
    vars: ["RESEND_API_KEY", "SUPPORT_EMAIL_TO"],
    optionalVars: ["SUPPORT_EMAIL_FROM"],
    setup:
      "Create a Resend API key (resend.com); supabase secrets set RESEND_API_KEY=... SUPPORT_EMAIL_TO=you@example.com. Tickets are stored and shown to staff even without it.",
  },
  {
    service: "cors",
    label: "Allowed web origins",
    required: false,
    vars: ["ALLOWED_ORIGINS"],
    setup: "supabase secrets set ALLOWED_ORIGINS=https://your-admin-host,https://your-web-app (comma-separated).",
  },
];

export type Env = (name: string) => string | undefined;

export interface Presence {
  service: string;
  label: string;
  required: boolean;
  configured: boolean;
  missing: string[];
  setup: string;
}

export function presence(env: Env): Presence[] {
  return SERVICES.map((s) => {
    const missing = s.vars.filter((v) => !(env(v) ?? "").trim());
    return {
      service: s.service,
      label: s.label,
      required: s.required,
      configured: missing.length === 0,
      missing,
      setup: s.setup,
    };
  });
}

export interface Validation {
  valid: boolean;
  message: string;
}

/** A safe, read-only live check. Messages never include secret material. */
export async function validate(
  service: string,
  env: Env,
  deps: { fetch?: typeof fetch; mediaRoundtrip?: () => Promise<boolean> } = {},
): Promise<Validation> {
  const f = deps.fetch ?? fetch;
  const spec = SERVICES.find((s) => s.service === service);
  if (!spec) return { valid: false, message: "Unknown service." };
  const missing = spec.vars.filter((v) => !(env(v) ?? "").trim());
  if (missing.length) return { valid: false, message: `Not configured: ${missing.join(", ")}.` };
  try {
    switch (service) {
      case "spotify": {
        const basic = btoa(`${env("SPOTIFY_CLIENT_ID")}:${env("SPOTIFY_CLIENT_SECRET")}`);
        const res = await f("https://accounts.spotify.com/api/token", {
          method: "POST",
          headers: { Authorization: `Basic ${basic}`, "Content-Type": "application/x-www-form-urlencoded" },
          body: "grant_type=client_credentials",
        });
        await res.body?.cancel();
        if (res.ok) return { valid: true, message: "Spotify accepted the client ID and secret." };
        return {
          valid: false,
          message: res.status === 400 || res.status === 401
            ? "Spotify rejected the client ID or secret."
            : `Spotify answered ${res.status}; try again later.`,
        };
      }
      case "media_keys": {
        const ok = deps.mediaRoundtrip ? await deps.mediaRoundtrip() : false;
        return ok
          ? { valid: true, message: "Active key encrypts and decrypts correctly." }
          : { valid: false, message: "The active key can't encrypt/decrypt; check MEDIA_KEKS and MEDIA_KEK_ACTIVE." };
      }
      case "revenuecat": {
        const ok = (env("REVENUECAT_WEBHOOK_AUTH") ?? "").length >= 24;
        return ok
          ? { valid: true, message: "Webhook secret is set and long enough." }
          : { valid: false, message: "Webhook secret is too short; use at least 24 random characters." };
      }
      case "cors": {
        const bad = (env("ALLOWED_ORIGINS") ?? "").split(",").map((o) => o.trim()).filter((o) =>
          o && !/^https:\/\/[^/]+$/.test(o)
        );
        return bad.length
          ? { valid: false, message: `${bad.length} origin(s) aren't https://host form.` }
          : { valid: true, message: "Origins look valid." };
      }
      default:
        return { valid: true, message: "Configured (no live check for this service)." };
    }
  } catch (_) {
    return { valid: false, message: "Couldn't reach the service." };
  }
}
