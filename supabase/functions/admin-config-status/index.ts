// Admin web app → Settings → Integrations & credentials.
// GET-like POST { action: "status" } | { action: "validate", service }
// Only admins on an MFA session (checked by the database's is_staff('admin')
// through admin_integration_status()). Reports configured / missing / valid;
// secret values are never returned, logged or stored.
import { admin, requireUser } from "../_shared/auth.ts";
import { handle, HttpError, json } from "../_shared/http.ts";
import { openSecret, sealSecret } from "../_shared/media_crypto.ts";
import { presence, SERVICES, validate } from "../_shared/config_status.ts";

const env = (name: string) => Deno.env.get(name);

async function mediaRoundtrip(): Promise<boolean> {
  try {
    const { sealed, kekId } = await sealSecret("config-check", "ok");
    return (await openSecret("config-check", sealed, kekId)) === "ok";
  } catch (_) {
    return false;
  }
}

Deno.serve((req) =>
  handle(req, async () => {
    if (req.method !== "POST") throw new HttpError(405, "method", "POST only.");
    const { asUser } = await requireUser(req);
    // Staff gate lives in the database (admin role + MFA session).
    const { error: forbidden } = await asUser.rpc("admin_integration_status");
    if (forbidden) throw new HttpError(403, "forbidden", "Admins only (with two-step verification).");

    const body = await req.json().catch(() => ({}));
    const now = presence(env);
    for (const p of now) {
      await admin.rpc("service_record_integration", {
        p_service: p.service, p_configured: p.configured, p_missing: p.missing,
        p_valid: null, p_message: null, p_validated: false,
      });
    }
    if (body.action === "validate") {
      if (!SERVICES.some((s) => s.service === body.service)) throw new HttpError(400, "bad_request", "Unknown service.");
      const v = await validate(body.service, env, { mediaRoundtrip });
      await admin.rpc("service_record_integration", {
        p_service: body.service, p_configured: now.find((p) => p.service === body.service)!.configured,
        p_missing: now.find((p) => p.service === body.service)!.missing,
        p_valid: v.valid, p_message: v.message, p_validated: true,
      });
    } else if (body.action !== "status") {
      throw new HttpError(400, "bad_request", "Unknown action.");
    }
    const { data: stored } = await asUser.rpc("admin_integration_status");
    const byService = new Map((stored ?? []).map((r: { service: string }) => [r.service, r]));
    return json(req, {
      services: now.map((p) => ({ ...p, ...(byService.get(p.service) ?? {}), label: p.label, required: p.required, setup: p.setup })),
    });
  }));
