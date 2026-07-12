const SENSITIVE_KEY = /authorization|cookie|credential|identity.?token|refresh.?token|access.?token|nonce|secret/i;
const JWT_LIKE = /\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/gu;
const BEARER = /Bearer\s+[A-Za-z0-9._~-]+/giu;

export function redactForLog(value: unknown, key = ""): unknown {
  if (SENSITIVE_KEY.test(key)) return "[REDACTED]";
  if (typeof value === "string") {
    return value.replace(BEARER, "Bearer [REDACTED]").replace(JWT_LIKE, "[REDACTED_JWT]");
  }
  if (Array.isArray(value)) return value.map((item) => redactForLog(item));
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).map(([childKey, childValue]) => [
        childKey,
        redactForLog(childValue, childKey),
      ]),
    );
  }
  return value;
}

export function logRequestFailure(record: {
  event: "request_failed";
  requestId: string;
  status: number;
  errorCode: string;
}): void {
  // This closed record deliberately excludes request headers, bodies, thrown errors, and tokens.
  console.error(JSON.stringify(record));
}
