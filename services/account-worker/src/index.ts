import {
  accountIdForAppleSubject,
  createOrGetAccount,
  deleteAccountData,
  getAccountProfile,
  pruneDeletionTombstones,
} from "./accounts";
import {
  exchangeAppleAuthorizationCode,
  loadAppleCredentialForDeletion,
  promoteStagedAppleRefreshToken,
  revokeAppleRefreshToken,
  verifyAppleIdentityToken,
} from "./apple";
import { constantTimeEqual, sha256 } from "./crypto";
import {
  consumeDeletionProof,
  DELETION_PROOF_SECONDS,
  issueDeletionProof,
} from "./deletion-proof";
import { AppError, authenticationFailed, badRequest, unauthorized } from "./errors";
import {
  emptyResponse,
  jsonResponse,
  optionalString,
  readJsonObject,
  rejectUnknownFields,
  requireString,
} from "./http";
import { logRequestFailure } from "./logging";
import { enforceRateLimit, RATE_LIMITS, requestNetworkIdentifier } from "./rate-limit";
import {
  prepareAppleRevocation,
  processAppleRevocationOutbox,
  stageAppleRevocation,
  tryImmediateAppleRevocation,
} from "./revocation-outbox";
import {
  authenticate,
  createSession,
  pruneExpiredSessions,
  revokeSession,
  rotateRefreshToken,
} from "./sessions";
import type { Env } from "./types";
import { claimUsername, suggestUsername } from "./usernames";

function requestId(request: Request): string {
  return request.headers.get("cf-ray")?.slice(0, 64) ?? crypto.randomUUID();
}

function rejectBrowserOrigin(request: Request): void {
  // This API is native-app-only. It intentionally emits no CORS allow headers.
  if (request.headers.has("origin")) {
    throw new AppError(403, "browser_origin_forbidden", "Browser-origin requests are not accepted.");
  }
}

export interface WorkerDependencies {
  verifyAppleIdentity: typeof verifyAppleIdentityToken;
  exchangeAppleCode: typeof exchangeAppleAuthorizationCode;
  promoteAppleToken: typeof promoteStagedAppleRefreshToken;
  revokeAppleToken: typeof revokeAppleRefreshToken;
}

const DEFAULT_DEPENDENCIES: WorkerDependencies = {
  verifyAppleIdentity: verifyAppleIdentityToken,
  exchangeAppleCode: exchangeAppleAuthorizationCode,
  promoteAppleToken: promoteStagedAppleRefreshToken,
  revokeAppleToken: revokeAppleRefreshToken,
};

async function stageAcquiredAppleToken(
  env: Env,
  refreshToken: string,
  now: number,
  dependencies: WorkerDependencies,
): Promise<Awaited<ReturnType<typeof stageAppleRevocation>>> {
  try {
    return await stageAppleRevocation(env, refreshToken, now);
  } catch {
    try {
      await dependencies.revokeAppleToken(env, refreshToken);
    } catch {
      // No AIC session is released when durable staging and immediate revocation both fail.
    }
    throw new AppError(503, "apple_credential_staging_unavailable", "Sign in is temporarily unavailable.");
  }
}

async function scheduleStagedRevocation(
  env: Env,
  context: ExecutionContext | undefined,
  outboxId: string,
  refreshToken: string,
  dependencies: WorkerDependencies,
): Promise<void> {
  const revocation = tryImmediateAppleRevocation(
    env,
    outboxId,
    refreshToken,
    (token) => dependencies.revokeAppleToken(env, token),
  );
  if (context) context.waitUntil(revocation);
  else await revocation;
}

async function handleRequest(
  request: Request,
  env: Env,
  dependencies: WorkerDependencies,
  context?: ExecutionContext,
): Promise<Response> {
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/$/u, "") || "/";

  if (request.method === "GET" && path === "/health") {
    return jsonResponse({ status: "ok" });
  }
  rejectBrowserOrigin(request);

  if (request.method === "POST" && path === "/v1/auth/apple/exchange") {
    const now = Math.floor(Date.now() / 1000);
    await enforceRateLimit(
      env.DB,
      env.RATE_LIMIT_PEPPER,
      RATE_LIMITS.appleExchange,
      requestNetworkIdentifier(request),
      now,
    );
    const body = await readJsonObject(request);
    rejectUnknownFields(body, ["identityToken", "authorizationCode", "rawNonce"]);
    const identityToken = requireString(body, "identityToken", { min: 64, max: 12_000 });
    const authorizationCode = requireString(body, "authorizationCode", { min: 8, max: 4_096 });
    const rawNonce = requireString(body, "rawNonce", { min: 16, max: 256 });
    const appleIdentity = await dependencies.verifyAppleIdentity(
      identityToken,
      rawNonce,
      env.APPLE_AUDIENCE,
    );
    const appleRefreshToken = await dependencies.exchangeAppleCode(
      env,
      authorizationCode,
      rawNonce,
      appleIdentity.subject,
    );
    const staged = await stageAcquiredAppleToken(
      env,
      appleRefreshToken,
      now,
      dependencies,
    );
    let promoted = false;
    try {
      const account = await createOrGetAccount(
        env,
        appleIdentity.subject,
        await sha256(identityToken),
        appleIdentity.issuedAt,
        appleIdentity.expiresAt,
        now,
      );
      promoted = await dependencies.promoteAppleToken(
        env,
        account.id,
        appleRefreshToken,
        staged.id,
        now,
      );
      if (!promoted) throw authenticationFailed();
      const session = await createSession(env, account.id, now);
      return jsonResponse({ account, ...session }, 200);
    } catch (error) {
      if (!promoted) {
        await scheduleStagedRevocation(
          env,
          context,
          staged.id,
          appleRefreshToken,
          dependencies,
        );
      }
      throw error;
    }
  }

  if (request.method === "POST" && path === "/v1/auth/apple/reauth") {
    const auth = await authenticate(request, env);
    const now = Math.floor(Date.now() / 1000);
    await enforceRateLimit(
      env.DB,
      env.RATE_LIMIT_PEPPER,
      RATE_LIMITS.appleReauth,
      auth.accountId,
      now,
    );
    const body = await readJsonObject(request);
    rejectUnknownFields(body, ["identityToken", "authorizationCode", "rawNonce"]);
    const identityToken = requireString(body, "identityToken", { min: 64, max: 12_000 });
    const authorizationCode = requireString(body, "authorizationCode", { min: 8, max: 4_096 });
    const rawNonce = requireString(body, "rawNonce", { min: 16, max: 256 });
    const appleIdentity = await dependencies.verifyAppleIdentity(
      identityToken,
      rawNonce,
      env.APPLE_AUDIENCE,
    );
    const appleRefreshToken = await dependencies.exchangeAppleCode(
      env,
      authorizationCode,
      rawNonce,
      appleIdentity.subject,
    );
    const staged = await stageAcquiredAppleToken(
      env,
      appleRefreshToken,
      now,
      dependencies,
    );
    let promoted = false;
    try {
      const proofAccountId = await accountIdForAppleSubject(env, appleIdentity.subject);
      if (!proofAccountId || !constantTimeEqual(proofAccountId, auth.accountId)) {
        throw unauthorized();
      }
      promoted = await dependencies.promoteAppleToken(
        env,
        auth.accountId,
        appleRefreshToken,
        staged.id,
        now,
      );
      if (!promoted) throw authenticationFailed();
      const reauthToken = await issueDeletionProof(env.DB, auth.accountId, now);
      return jsonResponse({ reauthToken, expiresIn: DELETION_PROOF_SECONDS });
    } catch (error) {
      if (!promoted) {
        await scheduleStagedRevocation(
          env,
          context,
          staged.id,
          appleRefreshToken,
          dependencies,
        );
      }
      throw error;
    }
  }

  if (request.method === "POST" && path === "/v1/auth/refresh") {
    const now = Math.floor(Date.now() / 1000);
    await enforceRateLimit(
      env.DB,
      env.RATE_LIMIT_PEPPER,
      RATE_LIMITS.sessionRefresh,
      requestNetworkIdentifier(request),
      now,
    );
    const body = await readJsonObject(request);
    rejectUnknownFields(body, ["refreshToken"]);
    const refreshToken = requireString(body, "refreshToken", { min: 40, max: 128 });
    const { account, session } = await rotateRefreshToken(
      env,
      refreshToken,
      now,
    );
    return jsonResponse({ account, ...session });
  }

  if (request.method === "POST" && path === "/v1/usernames/suggest") {
    const auth = await authenticate(request, env);
    await enforceRateLimit(
      env.DB,
      env.RATE_LIMIT_PEPPER,
      RATE_LIMITS.usernameSuggest,
      auth.accountId,
      Math.floor(Date.now() / 1000),
    );
    const body = await readJsonObject(request);
    rejectUnknownFields(body, ["preferredBase"]);
    const preferredBase = optionalString(body, "preferredBase", 80);
    const username = await suggestUsername(env.DB, preferredBase);
    return jsonResponse({ username, available: true });
  }

  if (request.method === "PUT" && path === "/v1/usernames/claim") {
    const auth = await authenticate(request, env);
    await enforceRateLimit(
      env.DB,
      env.RATE_LIMIT_PEPPER,
      RATE_LIMITS.usernameClaim,
      auth.accountId,
      Math.floor(Date.now() / 1000),
    );
    const body = await readJsonObject(request);
    rejectUnknownFields(body, ["username"]);
    const username = requireString(body, "username", { min: 1, max: 80 });
    const claimed = await claimUsername(
      env.DB,
      auth.accountId,
      username,
      Math.floor(Date.now() / 1000),
    );
    return jsonResponse({ username: claimed });
  }

  if (request.method === "GET" && path === "/v1/account") {
    const auth = await authenticate(request, env);
    const account = await getAccountProfile(env.DB, auth.accountId);
    if (!account || account.status !== "active") throw unauthorized();
    return jsonResponse({ account });
  }

  if (request.method === "POST" && path === "/v1/auth/logout") {
    const auth = await authenticate(request, env);
    const body = await readJsonObject(request);
    rejectUnknownFields(body, []);
    await revokeSession(
      env.DB,
      auth.accountId,
      auth.sessionId,
      Math.floor(Date.now() / 1000),
    );
    return emptyResponse();
  }

  if (request.method === "DELETE" && path === "/v1/account") {
    const auth = await authenticate(request, env);
    const body = await readJsonObject(request);
    rejectUnknownFields(body, ["confirmation", "reauthToken"]);
    if (body.confirmation !== "DELETE") {
      throw badRequest("deletion_not_confirmed", "Account deletion was not confirmed.");
    }
    const reauthToken = requireString(body, "reauthToken", { min: 40, max: 128 });
    const now = Math.floor(Date.now() / 1000);
    await consumeDeletionProof(env.DB, auth.accountId, reauthToken, now);
    let immediateRevocation: { outboxId: string; refreshToken: string } | undefined;
    let deleted = false;
    for (let attempt = 0; attempt < 3 && !deleted; attempt += 1) {
      const credential = await loadAppleCredentialForDeletion(env, auth.accountId);
      let queuedAppleRevocation:
        | {
            id: string;
            ciphertext: string;
            nonce: string;
            createdAt: number;
            nextAttemptAt: number;
          }
        | undefined;
      let candidateImmediateRevocation:
        | { outboxId: string; refreshToken: string }
        | undefined;
      if (credential?.refreshToken) {
        const prepared = await prepareAppleRevocation(
          credential.refreshToken,
          env.APPLE_TOKEN_ENCRYPTION_KEY,
          now,
        );
        queuedAppleRevocation = prepared;
        candidateImmediateRevocation = {
          outboxId: prepared.id,
          refreshToken: credential.refreshToken,
        };
      }
      deleted = await deleteAccountData(env.DB, auth.accountId, now, {
        expectedCredentialVersion: credential?.credentialVersion ?? null,
        ...(queuedAppleRevocation ? { queuedAppleRevocation } : {}),
      });
      if (deleted) immediateRevocation = candidateImmediateRevocation;
    }
    if (!deleted) {
      throw new AppError(409, "deletion_retry_required", "Sign in with Apple again to retry deletion.");
    }
    if (immediateRevocation) {
      const revocation = tryImmediateAppleRevocation(
        env,
        immediateRevocation.outboxId,
        immediateRevocation.refreshToken,
        (token) => dependencies.revokeAppleToken(env, token),
      );
      if (context) context.waitUntil(revocation);
      else await revocation;
    }
    return emptyResponse();
  }

  throw new AppError(404, "not_found", "Endpoint not found.");
}

export async function fetchHandler(
  request: Request,
  env: Env,
  context?: ExecutionContext,
  dependencyOverrides: Partial<WorkerDependencies> = {},
): Promise<Response> {
  const dependencies = { ...DEFAULT_DEPENDENCIES, ...dependencyOverrides };
  const id = requestId(request);
  try {
    return await handleRequest(request, env, dependencies, context);
  } catch (error) {
    const appError = error instanceof AppError
      ? error
      : new AppError(500, "internal_error", "The service could not complete the request.");
    if (appError.status >= 500) {
      logRequestFailure({
        event: "request_failed",
        requestId: id,
        status: appError.status,
        errorCode: appError.code,
      });
    }
    return jsonResponse(
      { error: { code: appError.code, message: appError.publicMessage, requestId: id } },
      appError.status,
    );
  }
}

export default {
  fetch: fetchHandler,
  scheduled(_controller, env, context): void {
    context.waitUntil(
      Promise.all([
        processAppleRevocationOutbox(env),
        pruneDeletionTombstones(env.DB),
        pruneExpiredSessions(env.DB),
      ]).then(() => undefined),
    );
  },
} satisfies ExportedHandler<Env>;
