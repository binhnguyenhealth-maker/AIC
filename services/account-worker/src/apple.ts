import {
  createRemoteJWKSet,
  errors as joseErrors,
  importPKCS8,
  jwtVerify,
  SignJWT,
} from "jose";
import type { JWTVerifyGetKey } from "jose";
import { constantTimeEqual, decryptAppleToken, encryptAppleToken, sha256 } from "./crypto";
import { AppError, authenticationFailed } from "./errors";
import { prepareAppleRevocation } from "./revocation-record";
import type { Env } from "./types";

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";
const APPLE_JWKS = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));

export interface VerifiedAppleIdentity {
  subject: string;
  issuedAt: number;
  expiresAt: number;
}

function appleConfigurationError(): AppError {
  return new AppError(503, "apple_configuration_unavailable", "Sign in is temporarily unavailable.");
}

function assertAppleServerConfig(env: Env): void {
  if (
    !env.APPLE_AUDIENCE ||
    !env.APPLE_TEAM_ID ||
    !env.APPLE_KEY_ID ||
    !env.APPLE_PRIVATE_KEY ||
    env.APPLE_TEAM_ID.startsWith("REPLACE_") ||
    env.APPLE_KEY_ID.startsWith("REPLACE_")
  ) {
    throw appleConfigurationError();
  }
}

async function createAppleClientSecret(env: Env): Promise<string> {
  assertAppleServerConfig(env);
  try {
    const privateKey = await importPKCS8(env.APPLE_PRIVATE_KEY.replaceAll("\\n", "\n"), "ES256");
    const now = Math.floor(Date.now() / 1000);
    return new SignJWT({})
      .setProtectedHeader({ alg: "ES256", kid: env.APPLE_KEY_ID, typ: "JWT" })
      .setIssuer(env.APPLE_TEAM_ID)
      .setSubject(env.APPLE_AUDIENCE)
      .setAudience(APPLE_ISSUER)
      .setIssuedAt(now)
      .setExpirationTime(now + 5 * 60)
      .sign(privateKey);
  } catch (error) {
    if (error instanceof AppError) throw error;
    throw appleConfigurationError();
  }
}

export async function verifyAppleIdentityToken(
  identityToken: string,
  rawNonce: string,
  audience: string,
  verificationKey: JWTVerifyGetKey = APPLE_JWKS,
): Promise<VerifiedAppleIdentity> {
  try {
    const { payload } = await jwtVerify(identityToken, verificationKey, {
      algorithms: ["RS256"],
      audience,
      issuer: APPLE_ISSUER,
      requiredClaims: ["sub", "iat", "exp", "nonce"],
      clockTolerance: 5,
      maxTokenAge: "10m",
    });

    if (
      typeof payload.sub !== "string" ||
      typeof payload.iat !== "number" ||
      typeof payload.exp !== "number"
    ) {
      throw authenticationFailed();
    }
    const expectedNonce = await sha256(rawNonce);
    if (typeof payload.nonce !== "string" || !constantTimeEqual(payload.nonce, expectedNonce)) {
      throw authenticationFailed();
    }
    return { subject: payload.sub, issuedAt: payload.iat, expiresAt: payload.exp };
  } catch (error) {
    if (error instanceof AppError) throw error;
    if (error instanceof joseErrors.JOSEError) {
      throw authenticationFailed();
    }
    throw new AppError(503, "apple_verification_unavailable", "Sign in is temporarily unavailable.");
  }
}

export async function exchangeAppleAuthorizationCode(
  env: Env,
  authorizationCode: string,
  rawNonce: string,
  expectedSubject: string,
): Promise<string> {
  const form = new URLSearchParams({
    client_id: env.APPLE_AUDIENCE,
    client_secret: await createAppleClientSecret(env),
    code: authorizationCode,
    grant_type: "authorization_code",
  });

  let response: Response;
  try {
    response = await fetch(APPLE_TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: form,
      signal: AbortSignal.timeout(8_000),
    });
  } catch {
    throw new AppError(503, "apple_exchange_unavailable", "Sign in is temporarily unavailable.");
  }
  if (!response.ok) {
    throw authenticationFailed();
  }

  let payload: unknown;
  try {
    payload = await response.json();
  } catch {
    throw new AppError(503, "apple_exchange_unavailable", "Sign in is temporarily unavailable.");
  }
  const tokenResponse = payload as { refresh_token?: unknown; id_token?: unknown };
  if (typeof tokenResponse.refresh_token !== "string" || typeof tokenResponse.id_token !== "string") {
    throw new AppError(503, "apple_exchange_unavailable", "Sign in is temporarily unavailable.");
  }

  const exchangedIdentity = await verifyAppleIdentityToken(
    tokenResponse.id_token,
    rawNonce,
    env.APPLE_AUDIENCE,
  );
  if (!constantTimeEqual(exchangedIdentity.subject, expectedSubject)) {
    throw authenticationFailed();
  }
  return tokenResponse.refresh_token;
}

export async function storeAppleRefreshToken(
  env: Env,
  accountId: string,
  refreshToken: string,
  now: number,
): Promise<void> {
  let encrypted: { ciphertext: string; nonce: string };
  try {
    encrypted = await encryptAppleToken(
      refreshToken,
      env.APPLE_TOKEN_ENCRYPTION_KEY,
      accountId,
    );
  } catch {
    throw appleConfigurationError();
  }
  const credentialVersion = crypto.randomUUID();
  const result = await env.DB
    .prepare(
      `INSERT INTO apple_credentials
       (account_id, refresh_token_ciphertext, encryption_nonce,
        credential_version, created_at, updated_at)
       SELECT id, ?, ?, ?, ?, ? FROM accounts
       WHERE id = ? AND status = 'active'
       ON CONFLICT(account_id) DO NOTHING`,
    )
    .bind(
      encrypted.ciphertext,
      encrypted.nonce,
      credentialVersion,
      now,
      now,
      accountId,
    )
    .run();
  if ((result.meta.changes ?? 0) !== 1) throw authenticationFailed();
}

export async function promoteStagedAppleRefreshToken(
  env: Env,
  accountId: string,
  refreshToken: string,
  stagedOutboxId: string,
  now: number,
): Promise<boolean> {
  let encrypted: { ciphertext: string; nonce: string };
  try {
    encrypted = await encryptAppleToken(
      refreshToken,
      env.APPLE_TOKEN_ENCRYPTION_KEY,
      accountId,
    );
  } catch {
    throw appleConfigurationError();
  }
  const previousCredential = await loadAppleCredentialForDeletion(env, accountId);
  const expectedCredentialVersion = previousCredential?.credentialVersion ?? null;
  const displacedRevocation = previousCredential?.refreshToken &&
      !constantTimeEqual(previousCredential.refreshToken, refreshToken)
    ? await prepareAppleRevocation(
        previousCredential.refreshToken,
        env.APPLE_TOKEN_ENCRYPTION_KEY,
        now,
      )
    : undefined;
  const credentialVersion = crypto.randomUUID();
  const credentialGuard = `(
    (? IS NULL AND NOT EXISTS (
      SELECT 1 FROM apple_credentials c WHERE c.account_id = accounts.id
    )) OR EXISTS (
      SELECT 1 FROM apple_credentials c
      WHERE c.account_id = accounts.id AND c.credential_version = ?
    )
  )`;
  const statements: D1PreparedStatement[] = [];
  if (displacedRevocation) {
    statements.push(
      env.DB
        .prepare(
          `INSERT INTO apple_revocation_outbox
           (id, refresh_token_ciphertext, encryption_nonce,
            attempt_count, created_at, next_attempt_at)
           SELECT ?, ?, ?, 0, ?, ? FROM accounts
           WHERE id = ? AND status = 'active'
             AND ${credentialGuard}`,
        )
        .bind(
          displacedRevocation.id,
          displacedRevocation.ciphertext,
          displacedRevocation.nonce,
          displacedRevocation.createdAt,
          displacedRevocation.nextAttemptAt,
          accountId,
          expectedCredentialVersion,
          expectedCredentialVersion,
        ),
    );
  }
  const promotionResultIndex = statements.length;
  statements.push(
    env.DB
      .prepare(
        `INSERT INTO apple_credentials
         (account_id, refresh_token_ciphertext, encryption_nonce,
          credential_version, created_at, updated_at)
         SELECT id, ?, ?, ?, ?, ? FROM accounts
         WHERE id = ? AND status = 'active'
           AND ${credentialGuard}
           AND EXISTS (SELECT 1 FROM apple_revocation_outbox WHERE id = ?)
           ${displacedRevocation
             ? "AND EXISTS (SELECT 1 FROM apple_revocation_outbox WHERE id = ?)"
             : ""}
         ON CONFLICT(account_id) DO UPDATE SET
           refresh_token_ciphertext = excluded.refresh_token_ciphertext,
           encryption_nonce = excluded.encryption_nonce,
           credential_version = excluded.credential_version,
           updated_at = excluded.updated_at`,
      )
      .bind(
        encrypted.ciphertext,
        encrypted.nonce,
        credentialVersion,
        now,
        now,
        accountId,
        expectedCredentialVersion,
        expectedCredentialVersion,
        stagedOutboxId,
        ...(displacedRevocation ? [displacedRevocation.id] : []),
      ),
  );
  statements.push(
    env.DB
      .prepare(
        `DELETE FROM apple_revocation_outbox
         WHERE id = ? AND EXISTS (
           SELECT 1 FROM apple_credentials
           WHERE account_id = ? AND credential_version = ?
         )`,
      )
      .bind(stagedOutboxId, accountId, credentialVersion),
  );
  const results = await env.DB.batch(statements);
  return (results[promotionResultIndex]?.meta.changes ?? 0) === 1;
}

export async function loadAppleCredentialForDeletion(
  env: Env,
  accountId: string,
): Promise<{ refreshToken: string | null; credentialVersion: string } | null> {
  const row = await env.DB
    .prepare(
      `SELECT refresh_token_ciphertext, encryption_nonce, credential_version
       FROM apple_credentials WHERE account_id = ? LIMIT 1`,
    )
    .bind(accountId)
    .first<{
      refresh_token_ciphertext: string;
      encryption_nonce: string;
      credential_version: string | null;
    }>();
  if (!row) return null;
  if (!row.credential_version) {
    throw new AppError(503, "account_deletion_unavailable", "Account deletion is temporarily unavailable.");
  }

  try {
    return {
      refreshToken: await decryptAppleToken(
        row.refresh_token_ciphertext,
        row.encryption_nonce,
        env.APPLE_TOKEN_ENCRYPTION_KEY,
        accountId,
      ),
      credentialVersion: row.credential_version,
    };
  } catch {
    throw new AppError(
      503,
      "account_deletion_unavailable",
      "Account deletion is temporarily unavailable.",
    );
  }
}

export async function revokeAppleRefreshToken(env: Env, refreshToken: string): Promise<void> {
  const form = new URLSearchParams({
    client_id: env.APPLE_AUDIENCE,
    client_secret: await createAppleClientSecret(env),
    token: refreshToken,
    token_type_hint: "refresh_token",
  });
  let response: Response;
  try {
    response = await fetch(APPLE_REVOKE_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: form,
      signal: AbortSignal.timeout(8_000),
    });
  } catch {
    throw new AppError(503, "account_deletion_unavailable", "Account deletion is temporarily unavailable.");
  }
  if (!response.ok) {
    throw new AppError(503, "account_deletion_unavailable", "Account deletion is temporarily unavailable.");
  }
}
