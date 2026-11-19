// Shared HTTP helpers: strict CORS, security headers, JSON errors that never leak internals.
const allowed = (Deno.env.get("ALLOWED_ORIGINS") ?? "").split(",").map((s) => s.trim()).filter(Boolean);

export function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  const h: Record<string, string> = {
    "Vary": "Origin",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Cross-Origin-Resource-Policy": "same-site",
  };
  // Mobile apps send no Origin; browsers must be on the allow-list.
  if (origin && allowed.includes(origin)) {
    h["Access-Control-Allow-Origin"] = origin;
    h["Access-Control-Allow-Headers"] = "authorization, content-type, apikey, x-client-info";
    h["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS";
    h["Access-Control-Max-Age"] = "600";
  }
  return h;
}

export function preflight(req: Request): Response | null {
  if (req.method !== "OPTIONS") return null;
  const origin = req.headers.get("Origin") ?? "";
  if (!allowed.includes(origin)) return new Response(null, { status: 403 });
  return new Response(null, { status: 204, headers: corsHeaders(req) });
}

export function json(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

export class HttpError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

export async function handle(req: Request, fn: () => Promise<Response>): Promise<Response> {
  const pre = preflight(req);
  if (pre) return pre;
  try {
    return await fn();
  } catch (e) {
    if (e instanceof HttpError) return json(req, { error: e.code, message: e.message }, e.status);
    console.error("unhandled", e instanceof Error ? e.name : "error"); // no payloads in logs
    return json(req, { error: "internal", message: "Something went wrong." }, 500);
  }
}
