// RevenueCat -> Supabase: keeps profiles.is_premium / premium_expires_at in sync.
// Deploy: supabase functions deploy revenuecat-webhook --no-verify-jwt
// Secrets: supabase secrets set REVENUECAT_WEBHOOK_AUTH=<value set in RevenueCat dashboard>
// RevenueCat app_user_id must be the Supabase auth user id (the app calls Purchases.logIn(uid)).
import { createClient } from "jsr:@supabase/supabase-js@2";

const ENTITLEMENT = "fast_track";
const GRANT = new Set([
  "INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION", "PRODUCT_CHANGE", "NON_RENEWING_PURCHASE", "SUBSCRIPTION_EXTENDED",
]);
const REVOKE = new Set(["EXPIRATION", "REFUND"]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  if (req.headers.get("Authorization") !== `Bearer ${Deno.env.get("REVENUECAT_WEBHOOK_AUTH")}`) {
    return new Response("Unauthorized", { status: 401 });
  }

  const { event } = await req.json();
  if (!event) return new Response("Bad request", { status: 400 });

  const entitlements: string[] = event.entitlement_ids ?? [];
  if (entitlements.length && !entitlements.includes(ENTITLEMENT)) return new Response("ignored");

  const userIds = [event.app_user_id, ...(event.aliases ?? [])].filter((id: string) => UUID.test(id));
  if (!userIds.length) return new Response("no supabase user", { status: 200 });

  let patch: Record<string, unknown> | null = null;
  if (GRANT.has(event.type)) {
    patch = {
      is_premium: true,
      premium_expires_at: event.expiration_at_ms ? new Date(event.expiration_at_ms).toISOString() : null,
    };
  } else if (REVOKE.has(event.type)) {
    patch = { is_premium: false, premium_expires_at: null };
  }
  // CANCELLATION / BILLING_ISSUE: access continues until EXPIRATION arrives.
  if (!patch) return new Response("noop");

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { error } = await admin.from("profiles").update(patch).in("id", userIds);
  if (error) return new Response(error.message, { status: 500 });
  return new Response("ok");
});
