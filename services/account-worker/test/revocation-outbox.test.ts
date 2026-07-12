import assert from "node:assert/strict";
import { afterEach, describe, it } from "node:test";
import type { Miniflare } from "miniflare";
import { deleteAccountData } from "../src/accounts";
import { encryptAppleToken } from "../src/crypto";
import {
  OUTBOX_MAX_AGE_SECONDS,
  processAppleRevocationOutbox,
} from "../src/revocation-outbox";
import type { Env } from "../src/types";
import { createTestDatabase, seedAccount } from "./helpers";

const instances: Miniflare[] = [];
afterEach(async () => {
  await Promise.all(instances.splice(0).map((instance) => instance.dispose()));
});

describe("Apple revocation outbox", () => {
  it("hard-deletes locally, retries an unlinkable encrypted token, and removes it on success", async () => {
    const { mf, db } = await createTestDatabase();
    instances.push(mf);
    const now = 1_700_000_000;
    const accountId = "account-outbox";
    const encryptionKey = btoa("o".repeat(32));
    const outboxId = crypto.randomUUID();
    await seedAccount(db, accountId, now);
    const encrypted = await encryptAppleToken("apple-refresh-for-retry", encryptionKey, outboxId);

    assert.equal(
      await deleteAccountData(db, accountId, now, {
        expectedCredentialVersion: null,
        queuedAppleRevocation: {
          id: outboxId,
          ciphertext: encrypted.ciphertext,
          nonce: encrypted.nonce,
          createdAt: Math.floor((now - 1) / 3600) * 3600,
          nextAttemptAt: now + 120,
        },
      }),
      true,
    );
    assert.equal(
      await db.prepare("SELECT id FROM accounts WHERE id = ?").bind(accountId).first(),
      null,
    );
    const timing = await db
      .prepare(
        `SELECT o.created_at, o.next_attempt_at, t.deleted_at
         FROM apple_revocation_outbox o CROSS JOIN deletion_tombstones t`,
      )
      .first<{ created_at: number; next_attempt_at: number; deleted_at: number }>();
    assert.ok(timing);
    assert.notEqual(timing.created_at, timing.deleted_at);
    assert.notEqual(timing.next_attempt_at, timing.deleted_at);
    const columns = await db
      .prepare("PRAGMA table_info(apple_revocation_outbox)")
      .all<{ name: string }>();
    assert.equal(
      columns.results.some((column) => /account|subject|username/u.test(column.name)),
      false,
    );

    const env = { DB: db, APPLE_TOKEN_ENCRYPTION_KEY: encryptionKey } as Env;
    assert.deepEqual(
      await processAppleRevocationOutbox(env, now + 120, async () => {
        throw new Error("simulated Apple outage");
      }),
      { processed: 1, revoked: 0, deferred: 1, expired: 0 },
    );
    let receivedToken = "";
    assert.deepEqual(
      await processAppleRevocationOutbox(env, now + 240, async (token) => {
        receivedToken = token;
      }),
      { processed: 1, revoked: 1, deferred: 0, expired: 0 },
    );
    assert.equal(receivedToken, "apple-refresh-for-retry");
    assert.equal(await db.prepare("SELECT id FROM apple_revocation_outbox").first(), null);
  });

  it("deletes residual ciphertext at the bounded retention limit", async () => {
    const { mf, db } = await createTestDatabase();
    instances.push(mf);
    const createdAt = 1_700_000_000;
    const encryptionKey = btoa("r".repeat(32));
    const outboxId = crypto.randomUUID();
    const encrypted = await encryptAppleToken("expired-refresh", encryptionKey, outboxId);
    await db
      .prepare(
        `INSERT INTO apple_revocation_outbox
         (id, refresh_token_ciphertext, encryption_nonce, attempt_count, created_at, next_attempt_at)
         VALUES (?, ?, ?, 0, ?, ?)`,
      )
      .bind(outboxId, encrypted.ciphertext, encrypted.nonce, createdAt, createdAt)
      .run();

    let revokeCalled = false;
    const result = await processAppleRevocationOutbox(
      { DB: db, APPLE_TOKEN_ENCRYPTION_KEY: encryptionKey } as Env,
      createdAt + OUTBOX_MAX_AGE_SECONDS,
      async () => {
        revokeCalled = true;
      },
    );
    assert.deepEqual(result, { processed: 1, revoked: 0, deferred: 0, expired: 1 });
    assert.equal(revokeCalled, false);
    assert.equal(await db.prepare("SELECT id FROM apple_revocation_outbox").first(), null);
    const counter = await db
      .prepare("SELECT metric, counter_value, updated_at FROM operational_counters")
      .first<{ metric: string; counter_value: number; updated_at: number }>();
    assert.deepEqual(counter, {
      metric: "apple_revocation_exhausted",
      counter_value: 1,
      updated_at: createdAt + OUTBOX_MAX_AGE_SECONDS,
    });
    const counterColumns = await db
      .prepare("PRAGMA table_info(operational_counters)")
      .all<{ name: string }>();
    assert.deepEqual(
      counterColumns.results.map((column) => column.name),
      ["metric", "counter_value", "updated_at"],
    );
  });
});
