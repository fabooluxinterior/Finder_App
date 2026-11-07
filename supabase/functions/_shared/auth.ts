import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { HttpError } from "./http.ts";

const url = Deno.env.get("SUPABASE_URL")!;
const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

export const admin: SupabaseClient = createClient(url, service, { auth: { persistSession: false } });

/** Validates the caller's JWT with Supabase Auth (server-side) and returns
 *  the user plus a client that acts with the user's own RLS permissions. */
export async function requireUser(req: Request) {
  const header = req.headers.get("Authorization") ?? "";
  if (!header.startsWith("Bearer ")) throw new HttpError(401, "unauthenticated", "Sign in required.");
  const jwt = header.slice(7);
  const { data, error } = await admin.auth.getUser(jwt);
  if (error || !data.user) throw new HttpError(401, "unauthenticated", "Session expired.");
  const asUser = createClient(url, anon, {
    auth: { persistSession: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  return { user: data.user, asUser };
}

export async function securityEvent(userId: string | null, kind: string, severity: "info" | "warning" | "critical", details: Record<string, unknown> = {}) {
  await admin.from("security_events").insert({ user_id: userId, kind, severity, details });
}

/** Fixed-window rate limit keyed by user (service-side). */
export async function rateLimit(userId: string, bucket: string, max: number, windowSeconds: number): Promise<void> {
  const { data, error } = await admin.rpc("service_rate_limit", {
    p_user: userId, p_bucket: bucket, p_max: max, p_window_seconds: windowSeconds,
  });
  if (error) throw error;
  if (data === false) throw new HttpError(429, "rate_limited", "Too many requests. Try again later.");
}
