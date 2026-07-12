import { hmacSha256 } from "./crypto";
import { AppError } from "./errors";

export interface RateLimitRule {
  bucket: string;
  limit: number;
  windowSeconds: number;
}

export const RATE_LIMITS = {
  appleExchange: { bucket: "apple_exchange", limit: 10, windowSeconds: 5 * 60 },
  appleReauth: { bucket: "apple_reauth", limit: 5, windowSeconds: 10 * 60 },
  sessionRefresh: { bucket: "session_refresh", limit: 20, windowSeconds: 5 * 60 },
  sessionRefreshPrincipal: {
    bucket: "session_refresh_principal",
    limit: 12,
    windowSeconds: 5 * 60,
  },
  usernameSuggest: { bucket: "username_suggest", limit: 30, windowSeconds: 60 },
  usernameClaim: { bucket: "username_claim", limit: 10, windowSeconds: 10 * 60 },
} as const satisfies Record<string, RateLimitRule>;

export function requestNetworkIdentifier(request: Request): string {
  // Cloudflare sets and normalizes this header at the edge. Never trust X-Forwarded-For.
  return request.headers.get("cf-connecting-ip") ?? "missing-edge-client-ip";
}

export async function enforceRateLimit(
  db: D1Database,
  pepper: string,
  rule: RateLimitRule,
  identifier: string,
  now: number,
): Promise<void> {
  const identifierHash = await hmacSha256(pepper, `${rule.bucket}:${identifier}`);
  const windowStart = Math.floor(now / rule.windowSeconds) * rule.windowSeconds;
  await db
    .prepare("DELETE FROM rate_limits WHERE window_start < ?")
    .bind(now - 24 * 60 * 60)
    .run();
  const row = await db
    .prepare(
      `INSERT INTO rate_limits
       (bucket, identifier_hash, window_start, request_count)
       VALUES (?, ?, ?, 1)
       ON CONFLICT(bucket, identifier_hash, window_start)
       DO UPDATE SET request_count = request_count + 1
       RETURNING request_count`,
    )
    .bind(rule.bucket, identifierHash, windowStart)
    .first<{ request_count: number }>();
  if (!row) throw new Error("rate limit update failed");
  if (row.request_count > rule.limit) {
    throw new AppError(429, "rate_limited", "Too many requests. Try again later.");
  }
}
