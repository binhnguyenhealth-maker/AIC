import { jwtVerify, SignJWT } from "jose";
import { randomToken, requireStrongSecret, sha256 } from "./crypto";
import { AppError, authenticationFailed, unauthorized } from "./errors";
import { bearerToken } from "./http";
import { enforceRateLimit, RATE_LIMITS } from "./rate-limit";
import type { AccountProfile, AuthContext, Env } from "./types";
import { getAccountProfile } from "./accounts";

const ACCESS_TOKEN_SECONDS = 15 * 60;
const REFRESH_TOKEN_SECONDS = 30 * 24 * 60 * 60;
export const SESSION_ABSOLUTE_SECONDS = 90 * 24 * 60 * 60;
export const REVOKED_SESSION_RETENTION_SECONDS = 24 * 60 * 60;
export const MAX_SESSION_ROTATIONS = 2048;

export interface IssuedSession {
  accessToken: string;
  accessTokenExpiresIn: number;
  refreshToken: string;
  refreshTokenExpiresIn: number;
}

function accessKey(env: Env): Uint8Array {
  return requireStrongSecret("ACCESS_TOKEN_SECRET", env.ACCESS_TOKEN_SECRET);
}

async function signAccessToken(
  env: Env,
  accountId: string,
  sessionId: string,
  now: number,
): Promise<string> {
  return new SignJWT({ sid: sessionId })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setSubject(accountId)
    .setIssuer(env.TOKEN_ISSUER)
    .setAudience(env.TOKEN_AUDIENCE)
    .setJti(crypto.randomUUID())
    .setIssuedAt(now)
    .setExpirationTime(now + ACCESS_TOKEN_SECONDS)
    .sign(accessKey(env));
}

export async function createSession(
  env: Env,
  accountId: string,
  now: number,
): Promise<IssuedSession> {
  const sessionId = crypto.randomUUID();
  const refreshToken = randomToken();
  const refreshTokenHash = await sha256(refreshToken);
  const result = await env.DB
    .prepare(
      `INSERT INTO sessions
       (id, account_id, refresh_token_hash, created_at, updated_at,
        expires_at, absolute_expires_at)
       SELECT ?, id, ?, ?, ?, ?, ? FROM accounts
       WHERE id = ? AND status = 'active'`,
    )
    .bind(
      sessionId,
      refreshTokenHash,
      now,
      now,
      now + REFRESH_TOKEN_SECONDS,
      now + SESSION_ABSOLUTE_SECONDS,
      accountId,
    )
    .run();
  if ((result.meta.changes ?? 0) !== 1) throw authenticationFailed();

  return {
    accessToken: await signAccessToken(env, accountId, sessionId, now),
    accessTokenExpiresIn: ACCESS_TOKEN_SECONDS,
    refreshToken,
    refreshTokenExpiresIn: REFRESH_TOKEN_SECONDS,
  };
}

export async function authenticate(request: Request, env: Env): Promise<AuthContext> {
  try {
    const token = bearerToken(request);
    const { payload } = await jwtVerify(token, accessKey(env), {
      algorithms: ["HS256"],
      audience: env.TOKEN_AUDIENCE,
      issuer: env.TOKEN_ISSUER,
      requiredClaims: ["sub", "sid", "iat", "exp", "jti"],
      clockTolerance: 5,
    });
    if (typeof payload.sub !== "string" || typeof payload.sid !== "string") throw unauthorized();

    const now = Math.floor(Date.now() / 1000);
    const row = await env.DB
      .prepare(
        `SELECT s.id
         FROM sessions s
         JOIN accounts a ON a.id = s.account_id
         WHERE s.id = ? AND s.account_id = ?
           AND s.revoked_at IS NULL AND s.expires_at > ?
           AND s.absolute_expires_at > ? AND a.status = 'active'
         LIMIT 1`,
      )
      .bind(payload.sid, payload.sub, now, now)
      .first<{ id: string }>();
    if (!row) throw unauthorized();
    return { accountId: payload.sub, sessionId: payload.sid };
  } catch {
    throw unauthorized();
  }
}

export async function rotateRefreshToken(
  env: Env,
  refreshToken: string,
  now: number,
): Promise<{ account: AccountProfile; session: IssuedSession }> {
  const oldHash = await sha256(refreshToken);
  const row = await env.DB
    .prepare(
      `SELECT s.id, s.account_id, s.absolute_expires_at, s.rotation_count
       FROM sessions s
       JOIN accounts a ON a.id = s.account_id
       WHERE s.refresh_token_hash = ? AND s.revoked_at IS NULL
         AND s.expires_at > ? AND s.absolute_expires_at > ? AND a.status = 'active'
       LIMIT 1`,
    )
    .bind(oldHash, now, now)
    .first<{
      id: string;
      account_id: string;
      absolute_expires_at: number;
      rotation_count: number;
    }>();
  if (!row) {
    const reused = await env.DB
      .prepare("SELECT session_id FROM refresh_token_history WHERE token_hash = ? LIMIT 1")
      .bind(oldHash)
      .first<{ session_id: string }>();
    if (reused) {
      await env.DB
        .prepare(
          `UPDATE sessions SET revoked_at = COALESCE(revoked_at, ?), updated_at = ?
           WHERE id = ?`,
        )
        .bind(now, now, reused.session_id)
        .run();
    }
    throw unauthorized();
  }
  if (row.rotation_count >= MAX_SESSION_ROTATIONS) {
    await revokeSession(env.DB, row.account_id, row.id, now);
    throw new AppError(
      401,
      "fresh_apple_sign_in_required",
      "Sign in with Apple again.",
    );
  }
  await enforceRateLimit(
    env.DB,
    env.RATE_LIMIT_PEPPER,
    RATE_LIMITS.sessionRefreshPrincipal,
    `${row.account_id}:${row.id}`,
    now,
  );

  const nextRefreshToken = randomToken();
  const nextHash = await sha256(nextRefreshToken);
  const nextExpiresAt = Math.min(
    now + REFRESH_TOKEN_SECONDS,
    row.absolute_expires_at,
  );
  const results = await env.DB.batch([
    env.DB
      .prepare(
        "INSERT OR IGNORE INTO refresh_token_history (token_hash, session_id, used_at) VALUES (?, ?, ?)",
      )
      .bind(oldHash, row.id, now),
    env.DB
      .prepare(
        `UPDATE sessions
         SET refresh_token_hash = ?, updated_at = ?, expires_at = ?
           , rotation_count = rotation_count + 1
         WHERE id = ? AND refresh_token_hash = ? AND revoked_at IS NULL
           AND expires_at > ? AND absolute_expires_at > ?
           AND rotation_count < ?`,
      )
      .bind(
        nextHash,
        now,
        nextExpiresAt,
        row.id,
        oldHash,
        now,
        now,
        MAX_SESSION_ROTATIONS,
      ),
  ]);
  if ((results[0]?.meta.changes ?? 0) !== 1 || (results[1]?.meta.changes ?? 0) !== 1) {
    await revokeSession(env.DB, row.account_id, row.id, now);
    throw unauthorized();
  }

  const account = await getAccountProfile(env.DB, row.account_id);
  if (!account || account.status !== "active") throw unauthorized();
  return {
    account,
    session: {
      accessToken: await signAccessToken(env, row.account_id, row.id, now),
      accessTokenExpiresIn: ACCESS_TOKEN_SECONDS,
      refreshToken: nextRefreshToken,
      refreshTokenExpiresIn: nextExpiresAt - now,
    },
  };
}

export async function revokeSession(
  db: D1Database,
  accountId: string,
  sessionId: string,
  now: number,
): Promise<void> {
  await db
    .prepare(
      `UPDATE sessions SET revoked_at = COALESCE(revoked_at, ?), updated_at = ?
       WHERE id = ? AND account_id = ?`,
    )
    .bind(now, now, sessionId, accountId)
    .run();
}

export async function pruneExpiredSessions(
  db: D1Database,
  now = Math.floor(Date.now() / 1000),
): Promise<number> {
  const result = await db
    .prepare(
      `DELETE FROM sessions
       WHERE expires_at <= ? OR absolute_expires_at <= ?
         OR (revoked_at IS NOT NULL AND revoked_at <= ?)
       RETURNING id`,
    )
    .bind(now, now, now - REVOKED_SESSION_RETENTION_SECONDS)
    .all<{ id: string }>();
  return result.results.length;
}
