import assert from "node:assert/strict";
import { afterEach, describe, it } from "node:test";
import type { Miniflare } from "miniflare";
import {
  createOrGetAccount,
  DELETION_TOMBSTONE_SECONDS,
  deleteAccountData,
  pruneDeletionTombstones,
} from "../src/accounts";
import {
  loadAppleCredentialForDeletion,
  promoteStagedAppleRefreshToken,
  storeAppleRefreshToken,
} from "../src/apple";
import { issueDeletionProof } from "../src/deletion-proof";
import { prepareAppleRevocation, stageAppleRevocation } from "../src/revocation-outbox";
import { authenticate, createSession, rotateRefreshToken } from "../src/sessions";
import type { Env } from "../src/types";
import { claimUsername } from "../src/usernames";
import { createTestDatabase, seedAccount } from "./helpers";

const instances: Miniflare[] = [];
afterEach(async () => {
  await Promise.all(instances.splice(0).map((instance) => instance.dispose()));
});

describe("account deletion", () => {
  it("atomically tombstones, hard-deletes, and cascades associated data", async () => {
    const { mf, db } = await createTestDatabase();
    instances.push(mf);
    const accountId = "account-delete";
    const now = 1_700_000_000;
    await seedAccount(db, accountId, now);
    await db
      .prepare(
        "INSERT INTO usernames (account_id, normalized, created_at, updated_at) VALUES (?, ?, ?, ?)",
      )
      .bind(accountId, "delete_me", now, now)
      .run();
    await db
      .prepare(
        `INSERT INTO sessions
         (id, account_id, refresh_token_hash, created_at, updated_at, expires_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
      )
      .bind("session-delete", accountId, "refresh-hash", now, now, now + 10_000)
      .run();
    await db
      .prepare(
        `INSERT INTO apple_credentials
         (account_id, refresh_token_ciphertext, encryption_nonce,
          credential_version, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)`,
      )
      .bind(accountId, "ciphertext", "nonce", "credential-version-delete", now, now)
      .run();

    assert.equal(
      await deleteAccountData(db, accountId, now + 100, {
        expectedCredentialVersion: "credential-version-delete",
      }),
      true,
    );
    const account = await db
      .prepare("SELECT id FROM accounts WHERE id = ?")
      .bind(accountId)
      .first();
    const username = await db
      .prepare("SELECT normalized FROM usernames WHERE account_id = ?")
      .bind(accountId)
      .first();
    const appleCredential = await db
      .prepare("SELECT account_id FROM apple_credentials WHERE account_id = ?")
      .bind(accountId)
      .first();
    const session = await db
      .prepare("SELECT id FROM sessions WHERE id = ?")
      .bind("session-delete")
      .first();
    const tombstone = await db
      .prepare("SELECT subject_hash, deleted_at FROM deletion_tombstones")
      .first<{ subject_hash: string; deleted_at: number }>();

    assert.equal(account, null);
    assert.equal(username, null);
    assert.equal(appleCredential, null);
    assert.equal(session, null);
    assert.deepEqual(tombstone, {
      subject_hash: `deletion-subject-${accountId}`,
      deleted_at: now + 100,
    });
    assert.equal(
      await deleteAccountData(db, accountId, now + 200, {
        expectedCredentialVersion: null,
      }),
      false,
    );
  });

  it("deterministically blocks stale in-flight writes while allowing a fresh clean account", async () => {
    const { mf, db } = await createTestDatabase();
    instances.push(mf);
    const now = Math.floor(Date.now() / 1000);
    const appleSubject = "same-apple-subject";
    const env = {
      DB: db,
      APPLE_SUBJECT_PEPPER: "test-apple-subject-pepper-with-32-plus-characters",
      DELETION_TOMBSTONE_PEPPER: "distinct-deletion-pepper-with-32-plus-characters",
      ACCESS_TOKEN_SECRET: "test-access-secret-with-more-than-32-characters",
      TOKEN_ISSUER: "https://api.example.test",
      TOKEN_AUDIENCE: "aic-ios",
      APPLE_TOKEN_ENCRYPTION_KEY: btoa("k".repeat(32)),
    } as Env;

    const oldAccount = await createOrGetAccount(
      env,
      appleSubject,
      "first-verified-identity-token-hash",
      now,
      now + 300,
      now,
    );
    await claimUsername(db, oldAccount.id, "old_username", now);
    const oldSession = await createSession(env, oldAccount.id, now);
    await storeAppleRefreshToken(env, oldAccount.id, "old-apple-refresh", now);
    await issueDeletionProof(db, oldAccount.id, now);
    const subjectHashes = await db
      .prepare(
        `SELECT apple_subject_hash, deletion_subject_hash
         FROM accounts WHERE id = ?`,
      )
      .bind(oldAccount.id)
      .first<{ apple_subject_hash: string; deletion_subject_hash: string }>();
    assert.ok(subjectHashes);
    assert.notEqual(subjectHashes.apple_subject_hash, subjectHashes.deletion_subject_hash);
    const credential = await loadAppleCredentialForDeletion(env, oldAccount.id);
    assert.ok(credential);

    assert.equal(
      await deleteAccountData(db, oldAccount.id, now + 1, {
        expectedCredentialVersion: credential.credentialVersion,
      }),
      true,
    );
    const oldAccessRequest = new Request("https://api.example.test/v1/account", {
      headers: { Authorization: `Bearer ${oldSession.accessToken}` },
    });
    await assert.rejects(authenticate(oldAccessRequest, env));
    await assert.rejects(rotateRefreshToken(env, oldSession.refreshToken, now + 2));
    await assert.rejects(createSession(env, oldAccount.id, now + 2));
    await assert.rejects(
      storeAppleRefreshToken(env, oldAccount.id, "late-apple-refresh", now + 2),
    );
    await assert.rejects(issueDeletionProof(db, oldAccount.id, now + 2));
    await assert.rejects(
      createOrGetAccount(
        env,
        appleSubject,
        "stale-in-flight-identity-token-hash",
        now,
        now + 300,
        now + 2,
      ),
    );
    const deletionTombstone = await db
      .prepare("SELECT subject_hash, deleted_at FROM deletion_tombstones")
      .first<{ subject_hash: string; deleted_at: number }>();
    assert.ok(deletionTombstone);
    assert.equal(deletionTombstone.deleted_at, now + 1);
    assert.equal(deletionTombstone.subject_hash, subjectHashes.deletion_subject_hash);

    const newAccount = await createOrGetAccount(
      env,
      appleSubject,
      "fresh-post-deletion-identity-token-hash",
      now + 3,
      now + 600,
      now + 3,
    );
    assert.notEqual(newAccount.id, oldAccount.id);
    assert.equal(newAccount.username, null);
    assert.equal(newAccount.status, "active");
    const newSubject = await db
      .prepare("SELECT deletion_subject_hash FROM accounts WHERE id = ?")
      .bind(newAccount.id)
      .first<{ deletion_subject_hash: string }>();
    assert.equal(newSubject?.deletion_subject_hash, deletionTombstone.subject_hash);
    const revivedOldUsername = await db
      .prepare("SELECT account_id FROM usernames WHERE normalized = 'old_username'")
      .first();
    assert.equal(revivedOldUsername, null);
  });

  it("prunes subject-hash tombstones after the 24-hour stale-token window", async () => {
    const { mf, db } = await createTestDatabase();
    instances.push(mf);
    const now = 1_700_100_000;
    await db
      .prepare("INSERT INTO deletion_tombstones (subject_hash, deleted_at) VALUES (?, ?), (?, ?)")
      .bind(
        "expired-subject-hash",
        now - DELETION_TOMBSTONE_SECONDS - 1,
        "recent-subject-hash",
        now - DELETION_TOMBSTONE_SECONDS,
      )
      .run();

    assert.equal(await pruneDeletionTombstones(db, now), 1);
    const remaining = await db
      .prepare("SELECT subject_hash FROM deletion_tombstones")
      .all<{ subject_hash: string }>();
    assert.deepEqual(remaining.results, [{ subject_hash: "recent-subject-hash" }]);
  });

  it("leaves the account active on a credential-version race and succeeds on retry", async () => {
    const { mf, db } = await createTestDatabase();
    instances.push(mf);
    const now = 1_700_200_000;
    const accountId = "account-version-race";
    const env = {
      DB: db,
      APPLE_TOKEN_ENCRYPTION_KEY: btoa("v".repeat(32)),
    } as Env;
    await seedAccount(db, accountId, now);
    await storeAppleRefreshToken(env, accountId, "apple-refresh-v1", now);
    const versionOne = await loadAppleCredentialForDeletion(env, accountId);
    assert.ok(versionOne);
    const stagedVersionTwo = await stageAppleRevocation(env, "apple-refresh-v2", now + 1);
    assert.equal(
      await promoteStagedAppleRefreshToken(
        env,
        accountId,
        "apple-refresh-v2",
        stagedVersionTwo.id,
        now + 1,
      ),
      true,
    );

    assert.equal(
      await deleteAccountData(db, accountId, now + 2, {
        expectedCredentialVersion: versionOne.credentialVersion,
      }),
      false,
    );
    const stillActive = await db
      .prepare("SELECT status FROM accounts WHERE id = ?")
      .bind(accountId)
      .first<{ status: string }>();
    assert.deepEqual(stillActive, { status: "active" });
    assert.equal(await db.prepare("SELECT subject_hash FROM deletion_tombstones").first(), null);

    const versionTwo = await loadAppleCredentialForDeletion(env, accountId);
    assert.ok(versionTwo);
    assert.notEqual(versionTwo.credentialVersion, versionOne.credentialVersion);
    const versionTwoRevocation = await prepareAppleRevocation(
      versionTwo.refreshToken ?? "",
      env.APPLE_TOKEN_ENCRYPTION_KEY,
      now + 3,
    );
    assert.equal(
      await deleteAccountData(db, accountId, now + 3, {
        expectedCredentialVersion: versionTwo.credentialVersion,
        queuedAppleRevocation: versionTwoRevocation,
      }),
      true,
    );
    assert.equal(await db.prepare("SELECT id FROM accounts WHERE id = ?").bind(accountId).first(), null);
    assert.equal(
      (await db.prepare("SELECT COUNT(*) AS count FROM apple_revocation_outbox").first<{ count: number }>())?.count,
      2,
    );
  });
});
