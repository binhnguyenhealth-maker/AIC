import { decryptAppleToken } from "./crypto";
import { revokeAppleRefreshToken } from "./apple";
import { prepareAppleRevocation } from "./revocation-record";
import type { PreparedAppleRevocation } from "./revocation-record";
export { prepareAppleRevocation } from "./revocation-record";
export type { PreparedAppleRevocation } from "./revocation-record";
import type { Env } from "./types";

interface OutboxRow {
  id: string;
  refresh_token_ciphertext: string;
  encryption_nonce: string;
  attempt_count: number;
  created_at: number;
}

export interface OutboxRunResult {
  processed: number;
  revoked: number;
  deferred: number;
  expired: number;
}

export const OUTBOX_MAX_ATTEMPTS = 20;
export const OUTBOX_MAX_AGE_SECONDS = 30 * 24 * 60 * 60;

export async function stageAppleRevocation(
  env: Env,
  refreshToken: string,
  now: number,
): Promise<PreparedAppleRevocation> {
  const prepared = await prepareAppleRevocation(
    refreshToken,
    env.APPLE_TOKEN_ENCRYPTION_KEY,
    now,
  );
  await env.DB
    .prepare(
      `INSERT INTO apple_revocation_outbox
       (id, refresh_token_ciphertext, encryption_nonce,
        attempt_count, created_at, next_attempt_at)
       VALUES (?, ?, ?, 0, ?, ?)`,
    )
    .bind(
      prepared.id,
      prepared.ciphertext,
      prepared.nonce,
      prepared.createdAt,
      prepared.nextAttemptAt,
    )
    .run();
  return prepared;
}

export async function tryImmediateAppleRevocation(
  env: Env,
  outboxId: string,
  refreshToken: string,
  revoke: (token: string) => Promise<void> = (token) => revokeAppleRefreshToken(env, token),
): Promise<boolean> {
  try {
    await revoke(refreshToken);
    await env.DB.prepare("DELETE FROM apple_revocation_outbox WHERE id = ?").bind(outboxId).run();
    return true;
  } catch {
    return false;
  }
}

function retryDelaySeconds(attemptCount: number): number {
  return Math.min(24 * 60 * 60, 60 * 2 ** Math.min(attemptCount, 10));
}

async function exhaustOutboxItem(db: D1Database, id: string, now: number): Promise<void> {
  await db.batch([
    db
      .prepare(
        `INSERT INTO operational_counters (metric, counter_value, updated_at)
         SELECT 'apple_revocation_exhausted', 1, ?
         FROM apple_revocation_outbox WHERE id = ?
         ON CONFLICT(metric) DO UPDATE SET
           counter_value = operational_counters.counter_value + 1,
           updated_at = excluded.updated_at`,
      )
      .bind(now, id),
    db.prepare("DELETE FROM apple_revocation_outbox WHERE id = ?").bind(id),
  ]);
}

export async function processAppleRevocationOutbox(
  env: Env,
  now = Math.floor(Date.now() / 1000),
  revoke: (refreshToken: string) => Promise<void> = (token) => revokeAppleRefreshToken(env, token),
): Promise<OutboxRunResult> {
  const due = await env.DB
    .prepare(
      `SELECT id, refresh_token_ciphertext, encryption_nonce, attempt_count, created_at
       FROM apple_revocation_outbox
       WHERE next_attempt_at <= ? OR attempt_count >= ? OR created_at <= ?
       ORDER BY next_attempt_at, created_at
       LIMIT 25`,
    )
    .bind(now, OUTBOX_MAX_ATTEMPTS, now - OUTBOX_MAX_AGE_SECONDS)
    .all<OutboxRow>();

  let revoked = 0;
  let deferred = 0;
  let expired = 0;
  for (const row of due.results) {
    if (
      row.attempt_count >= OUTBOX_MAX_ATTEMPTS ||
      now - row.created_at >= OUTBOX_MAX_AGE_SECONDS
    ) {
      await exhaustOutboxItem(env.DB, row.id, now);
      expired += 1;
      continue;
    }
    try {
      const refreshToken = await decryptAppleToken(
        row.refresh_token_ciphertext,
        row.encryption_nonce,
        env.APPLE_TOKEN_ENCRYPTION_KEY,
        row.id,
      );
      await revoke(refreshToken);
      await env.DB.prepare("DELETE FROM apple_revocation_outbox WHERE id = ?").bind(row.id).run();
      revoked += 1;
    } catch {
      const nextAttemptCount = row.attempt_count + 1;
      if (
        nextAttemptCount >= OUTBOX_MAX_ATTEMPTS ||
        now - row.created_at >= OUTBOX_MAX_AGE_SECONDS
      ) {
        await exhaustOutboxItem(env.DB, row.id, now);
        expired += 1;
        continue;
      }
      await env.DB
        .prepare(
          `UPDATE apple_revocation_outbox
           SET attempt_count = ?, last_attempt_at = ?, next_attempt_at = ?
           WHERE id = ?`,
        )
        .bind(
          nextAttemptCount,
          now,
          now + retryDelaySeconds(nextAttemptCount),
          row.id,
        )
        .run();
      deferred += 1;
    }
  }
  return { processed: due.results.length, revoked, deferred, expired };
}
