// New-chat-message push: called by the database (pg_net) right after a message is stored.
// Messages are end-to-end encrypted, so the server never knows the content: the notification only says
// who wrote. Authenticated with a shared secret header, not a user JWT.

/** Constant-time comparison of the shared secret. */
export function secretMatches(given: string | null, expected: string | undefined): boolean {
  if (!given || !expected || given.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < given.length; i++) diff |= given.charCodeAt(i) ^ expected.charCodeAt(i);
  return diff === 0;
}

export function firstName(fullName: string | null | undefined): string {
  const n = (fullName ?? "").trim().split(/\s+/)[0] ?? "";
  return n.slice(0, 30) || "Someone";
}

export function messageNotice(senderFullName: string | null | undefined): { title: string; body: string } {
  return { title: firstName(senderFullName), body: "Sent you a message" };
}

export const isUuid = (v: unknown): v is string =>
  typeof v === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
