import assert from "node:assert/strict";
import { afterEach, describe, it } from "node:test";
import type { Miniflare } from "miniflare";
import { createOrGetAccount, deleteAccountData } from "../src/accounts";
import {
  loadAppleCredentialForDeletion,
  promoteStagedAppleRefreshToken,
  storeAppleRefreshToken,
} from "../src/apple";
import { decryptAppleToken } from "../src/crypto";
import { issueDeletionProof } from "../src/deletion-proof";
import { fetchHandler, type WorkerDependencies } from "../src/index";
import {
  prepareAppleRevocation,
  processAppleRevocationOutbox,
} from "../src/revocation-outbox";
import {
  createSession,
  MAX_SESSION_ROTATIONS,
  pruneExpiredSessions,
  REVOKED_SESSION_RETENTION_SECONDS,
} from "../src/sessions";
import type { Env } from "../src/types";
import { claimUsername } from "../src/usernames";
import { createTestDatabase } from "./helpers";

const instances: Miniflare[] = [];
afterEach(async () => {
  await Promise.all(instances.splice(0).map((instance) => instance.dispose()));
});

function testEnv(db: D1Database): Env {
  return {
    DB: db,
    APPLE_AUDIENCE: "com.binhnguyenhealth.aic",
    APPLE_TEAM_ID: "test-team",
    APPLE_KEY_ID: "test-key",
    APPLE_PRIVATE_KEY: "unused-in-injected-tests",
    APPLE_TOKEN_ENCRYPTION_KEY: btoa("e".repeat(32)),
    APPLE_SUBJECT_PEPPER: "endpoint-apple-subject-pepper-with-32-characters",
    DELETION_TOMBSTONE_PEPPER: "endpoint-deletion-pepper-distinct-32-characters",
    ACCESS_TOKEN_SECRET: "endpoint-access-secret-with-more-than-32-characters",
    RATE_LIMIT_PEPPER: "endpoint-rate-limit-pepper-with-more-than-32-characters",
    TOKEN_ISSUER: "https://api.example.test",
    TOKEN_AUDIENCE: "aic-ios",
  };
}

async function createAccount(
  env: Env,
  appleSubject: string,
  now: number,
): Promise<{ id: string; username: string | null; status: "active" | "disabled" }> {
  return createOrGetAccount(
    env,
    appleSubject,
    crypto.randomUUID(),
    now,
    now + 300,
    now,
  );
}

function appleBody(): string {
  return JSON.stringify({
    identityToken: "i".repeat(128),
    authorizationCode: "authorization-code",
    rawNonce: "raw-nonce-at-least-sixteen",
  });
}

async function stagedToken(db: D1Database, env: Env): Promise<string> {
  const row = await db
    .prepare(
      `SELECT id, refresh_token_ciphertext, encryption_nonce
       FROM apple_revocation_outbox LIMIT 1`,
    )
    .first<{ id: string; refresh_token_ciphertext: string; encryption_nonce: string }>();
  assert.ok(row);
  return decryptAppleToken(
    row.refresh_token_ciphertext,
    row.encryption_nonce,
    env.APPLE_TOKEN_ENCRYPTION_KEY,
    row.id,
  );
}

describe("endpoint lifecycle gates", () => {
  it("revokes the displaced credential after a normal reauth replacement", async () => {
    const { mf, db } = await createTestDatabase();
    instances.push(mf);
    const env = testEnv(db);
    const now = Math.floor(Date.now() / 1000);
    const subject = "normal-reauth-replacement-subject";
    const account = await createAccount(env, subject, now - 10);
    await storeAppleRefreshToken(env, account.id, "normal-reauth-refresh-v1", now - 5);
    const session = await createSession(env, account.id, now - 1);
    const dependencies: Partial<WorkerDependencies> = {
      verifyAppleIdentity: async () => ({
        subject,
        issuedAt: now - 5,
        expiresAt: now + 300,
      }),
      exchangeAppleCode: async () => "normal-reauth-refresh-v2",
    };

    const response = await fetchHandler(
      new Request("https://api.example.test/v1/auth/apple/reauth", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${session.accessToken}`,
          "Content-Type": "application/json",
        },
        body: appleBody(),
      }),
      env,
      undefined,
      dependencies,
    );
    assert.equal(response.status, 200);
    assert.equal(
      (await loadAppleCredentialForDeletion(env, account.id))?.refreshToken,
      "normal-reauth-refresh-v2",
    );

    const revoked: string[] = [];
    const result = await processAppleRevocationOutbox(
      env,
      now + 301,
      async (refreshToken) => {
        revoked.push(refreshToken);
      },
    );
    assert.deepEqual(result, { processed: 1, revoked: 1, deferred: 0, expired: 0 });
    assert.deepEqual(revoked, ["normal-reauth-refresh-v1"]);
  });

  it("preserves both distinct credentials across reauth promotion and deletion interleaving", async () => {
    const { mf, db } = await createTestDatabase();
    instances.push(mf);
    const env = testEnv(db);
    const now = Math.floor(Date.now() / 1000);
    const subject = "reauth-replacement-delete-race-subject";
    const account = await createAccount(env, subject, now - 10);
    await storeAppleRefreshToken(env, account.id, "race-refresh-v1", now - 5);
    const deletionSnapshot = await loadAppleCredentialForDeletion(env, account.id);
    assert.ok(deletionSnapshot?.refreshToken);
    const staleDeletionRevocation = await prepareAppleRevocation(
      deletionSnapshot.refreshToken,
      env.APPLE_TOKEN_ENCRYPTION_KEY,
      now,
    );
    const session = await createSession(env, account.id, now - 1);
    const dependencies: Partial<WorkerDependencies> = {
      verifyAppleIdentity: async () => ({
        subject,
        issuedAt: now - 5,
        expiresAt: now + 300,
      }),
      exchangeAppleCode: async () => "race-refresh-v2",
      promoteAppleToken: async (
        promoteEnv,
        accountId,
        refreshToken,
        stagedOutboxId,
        promoteNow,
      ) => {
        const promoted = await promoteStagedAppleRefreshToken(
          promoteEnv,
          accountId,
          refreshToken,
          stagedOutboxId,
          promoteNow,
        );
        assert.equal(promoted, true);
        assert.equal(
          await deleteAccountData(db, accountId, now, {
            expectedCredentialVersion: deletionSnapshot.credentialVersion,
            queuedAppleRevocation: staleDeletionRevocation,
          }),
          false,
        );
        const currentCredential = await loadAppleCredentialForDeletion(env, accountId);
        assert.equal(currentCredential?.refreshToken, "race-refresh-v2");
        assert.ok(currentCredential);
        const currentRevocation = await prepareAppleRevocation(
          currentCredential.refreshToken ?? "",
          env.APPLE_TOKEN_ENCRYPTION_KEY,
          now,
        );
        assert.equal(
          await deleteAccountData(db, accountId, now, {
            expectedCredentialVersion: currentCredential.credentialVersion,
            queuedAppleRevocation: currentRevocation,
          }),
          true,
        );
        return promoted;
      },
    };

    const response = await fetchHandler(
      new Request("https://api.example.test/v1/auth/apple/reauth", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${session.accessToken}`,
          "Content-Type": "application/json",
        },
        body: appleBody(),
      }),
      env,
      undefined,
      dependencies,
    );
    assert.equal(response.status, 401);
    assert.equal(await db.prepare("SELECT id FROM accounts WHERE id = ?").bind(account.id).first(), null);

    const revoked: string[] = [];
    const result = await processAppleRevocationOutbox(
      env,
      now + 301,
      async (refreshToken) => {
        revoked.push(refreshToken);
      },
    );
    assert.deepEqual(result, { processed: 2, revoked: 2, deferred: 0, expired: 0 });
    assert.deepEqual(new Set(revoked), new Set(["race-refresh-v1", "race-refresh-v2"]));
  });

  it("durably queues the exact exchange token when deletion wins the account race", async () => {
    const { mf, db } = await createTestDatabase();
    instances.push(mf);
    const env = testEnv(db);
    const now = Math.floor(Date.now() / 1000);
    const subject = "exchange-race-subject";
    const oldAccount = await createAccount(env, subject, now - 10);
    const dependencies: Partial<WorkerDependencies> = {
      verifyAppleIdentity: async () => ({
        subject,
        issuedAt: now - 5,
        expiresAt: now + 300,
      }),
      exchangeAppleCode: async () => "exchange-refresh-after-delete",
      promoteAppleToken: async (
        promoteEnv,
        accountId,
        refreshToken,
        stagedOutboxId,
        promoteNow,
      ) => {
        assert.equal(
          await deleteAccountData(db, accountId, now, {
            expectedCredentialVersion: null,
          }),
          true,
        );
        return promoteStagedAppleRefreshToken(
          promoteEnv,
          accountId,
          refreshToken,
          stagedOutboxId,
          promoteNow,
        );
      },
      revokeAppleToken: async () => {
        throw new Error("simulated Apple outage");
      },
    };

    const response = await fetchHandler(
      new Request("https://api.example.test/v1/auth/apple/exchange", {
        method: "POST",
        headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.20" },
        body: appleBody(),
      }),
      env,
      undefined,
      dependencies,
    );
    assert.equal(response.status, 401);
    assert.equal(await stagedToken(db, env), "exchange-refresh-after-delete");
    assert.equal(await db.prepare("SELECT id FROM accounts").first(), null);
  });

  it("durably queues the exact reauth token when deletion wins after bearer authentication", async () => {
    const { mf, db } = await createTestDatabase();
    instances.push(mf);
    const env = testEnv(db);
    const now = Math.floor(Date.now() / 1000);
    const subject = "reauth-race-subject";
    const account = await createAccount(env, subject, now - 10);
    const session = await createSession(env, account.id, now - 1);
    const dependencies: Partial<WorkerDependencies> = {
      verifyAppleIdentity: async () => {
        return { subject, issuedAt: now - 5, expiresAt: now + 300 };
      },
      exchangeAppleCode: async () => "reauth-refresh-after-delete",
      promoteAppleToken: async (
        promoteEnv,
        accountId,
        refreshToken,
        stagedOutboxId,
        promoteNow,
      ) => {
        assert.equal(
          await deleteAccountData(db, accountId, now, {
            expectedCredentialVersion: null,
          }),
          true,
        );
        return promoteStagedAppleRefreshToken(
          promoteEnv,
          accountId,
          refreshToken,
          stagedOutboxId,
          promoteNow,
        );
      },
      revokeAppleToken: async () => {
        throw new Error("simulated Apple outage");
      },
    };

    const response = await fetchHandler(
      new Request("https://api.example.test/v1/auth/apple/reauth", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${session.accessToken}`,
          "Content-Type": "application/json",
        },
        body: appleBody(),
      }),
      env,
      undefined,
      dependencies,
    );
    assert.equal(response.status, 401);
    assert.equal(await stagedToken(db, env), "reauth-refresh-after-delete");
    assert.equal(await db.prepare("SELECT id FROM accounts").first(), null);
  });

  it("fails account deletion closed when the retained Apple credential cannot decrypt", async () => {
    const { mf, db } = await createTestDatabase();
    instances.push(mf);
    const env = testEnv(db);
    const now = Math.floor(Date.now() / 1000);
    const account = await createAccount(env, "corrupt-credential-subject", now);
    await claimUsername(db, account.id, "keep_until_safe", now);
    await storeAppleRefreshToken(env, account.id, "valid-before-corruption", now);
    await db
      .prepare("UPDATE apple_credentials SET refresh_token_ciphertext = 'corrupt' WHERE account_id = ?")
      .bind(account.id)
      .run();
    const session = await createSession(env, account.id, now);
    const proof = await issueDeletionProof(db, account.id, now);

    const response = await fetchHandler(
      new Request("https://api.example.test/v1/account", {
        method: "DELETE",
        headers: {
          Authorization: `Bearer ${session.accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ confirmation: "DELETE", reauthToken: proof }),
      }),
      env,
    );
    assert.equal(response.status, 503);
    assert.deepEqual(
      await db.prepare("SELECT status FROM accounts WHERE id = ?").bind(account.id).first(),
      { status: "active" },
    );
    assert.deepEqual(
      await db.prepare("SELECT normalized FROM usernames WHERE account_id = ?").bind(account.id).first(),
      { normalized: "keep_until_safe" },
    );
    assert.ok(
      await db.prepare("SELECT account_id FROM apple_credentials WHERE account_id = ?").bind(account.id).first(),
    );
  });

  it("prevents multi-IP refresh bypass with a session-family bucket", async () => {
    const actualDateNow = Date.now;
    const fixedNow = (Math.floor(actualDateNow() / 300_000) * 300 + 10) * 1000;
    Date.now = () => fixedNow;
    try {
      const { mf, db } = await createTestDatabase();
      instances.push(mf);
      const env = testEnv(db);
      const now = Math.floor(Date.now() / 1000);
      const account = await createAccount(env, "multi-ip-refresh-subject", now);
      let refreshToken = (await createSession(env, account.id, now)).refreshToken;

      for (let attempt = 0; attempt < 12; attempt += 1) {
        const response = await fetchHandler(
          new Request("https://api.example.test/v1/auth/refresh", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "CF-Connecting-IP": `203.0.113.${attempt + 30}`,
            },
            body: JSON.stringify({ refreshToken }),
          }),
          env,
        );
        assert.equal(response.status, 200);
        refreshToken = (await response.json() as { refreshToken: string }).refreshToken;
      }
      const blocked = await fetchHandler(
        new Request("https://api.example.test/v1/auth/refresh", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "CF-Connecting-IP": "198.51.100.200",
          },
          body: JSON.stringify({ refreshToken }),
        }),
        env,
      );
      assert.equal(blocked.status, 429);
    } finally {
      Date.now = actualDateNow;
    }
  });

  it("revokes the session at the hard rotation ceiling", async () => {
    const { mf, db } = await createTestDatabase();
    instances.push(mf);
    const env = testEnv(db);
    const now = Math.floor(Date.now() / 1000);
    const account = await createAccount(env, "rotation-ceiling-subject", now);
    const session = await createSession(env, account.id, now);
    await db
      .prepare("UPDATE sessions SET rotation_count = ? WHERE account_id = ?")
      .bind(MAX_SESSION_ROTATIONS - 1, account.id)
      .run();

    const lastAllowed = await fetchHandler(
      new Request("https://api.example.test/v1/auth/refresh", {
        method: "POST",
        headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.88" },
        body: JSON.stringify({ refreshToken: session.refreshToken }),
      }),
      env,
    );
    assert.equal(lastAllowed.status, 200);
    const nextToken = (await lastAllowed.json() as { refreshToken: string }).refreshToken;
    const blocked = await fetchHandler(
      new Request("https://api.example.test/v1/auth/refresh", {
        method: "POST",
        headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.89" },
        body: JSON.stringify({ refreshToken: nextToken }),
      }),
      env,
    );
    assert.equal(blocked.status, 401);
    assert.equal((await blocked.json() as { error: { code: string } }).error.code, "fresh_apple_sign_in_required");
    const row = await db
      .prepare("SELECT revoked_at, rotation_count FROM sessions WHERE account_id = ?")
      .bind(account.id)
      .first<{ revoked_at: number | null; rotation_count: number }>();
    const revokedAt = row?.revoked_at;
    assert.ok(revokedAt);
    assert.equal(row?.rotation_count, MAX_SESSION_ROTATIONS);
    const historyCount = await db
      .prepare("SELECT COUNT(*) AS count FROM refresh_token_history WHERE session_id IN (SELECT id FROM sessions WHERE account_id = ?)")
      .bind(account.id)
      .first<{ count: number }>();
    assert.equal(historyCount?.count, 1);
    assert.equal(
      await pruneExpiredSessions(db, revokedAt + REVOKED_SESSION_RETENTION_SECONDS),
      1,
    );
    assert.equal(
      await db.prepare("SELECT id FROM sessions WHERE account_id = ?").bind(account.id).first(),
      null,
    );
    assert.equal(
      await db.prepare("SELECT token_hash FROM refresh_token_history LIMIT 1").first(),
      null,
    );
  });
});
