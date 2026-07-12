import { AppError, authenticationFailed } from "./errors";
import { hmacSha256 } from "./crypto";
import type { AccountProfile, Env } from "./types";

interface AccountRow {
  id: string;
  status: "active" | "disabled";
  username: string | null;
}

export const DELETION_TOMBSTONE_SECONDS = 24 * 60 * 60;

export async function getAccountProfile(
  db: D1Database,
  accountId: string,
): Promise<AccountProfile | null> {
  const row = await db
    .prepare(
      `SELECT a.id, a.status, u.normalized AS username
       FROM accounts a
       LEFT JOIN usernames u ON u.account_id = a.id
       WHERE a.id = ?
       LIMIT 1`,
    )
    .bind(accountId)
    .first<AccountRow>();
  return row ? { id: row.id, username: row.username, status: row.status } : null;
}

export async function createOrGetAccount(
  env: Env,
  appleSubject: string,
  identityTokenHash: string,
  tokenIssuedAt: number,
  tokenExpiresAt: number,
  now: number,
): Promise<AccountProfile> {
  const subjectHash = await hmacSha256(env.APPLE_SUBJECT_PEPPER, appleSubject);
  const deletionSubjectHash = await hmacSha256(
    env.DELETION_TOMBSTONE_PEPPER,
    appleSubject,
  );
  const candidateId = crypto.randomUUID();
  const results = await env.DB.batch([
    env.DB
      .prepare("DELETE FROM deletion_tombstones WHERE deleted_at < ?")
      .bind(now - DELETION_TOMBSTONE_SECONDS),
    env.DB.prepare("DELETE FROM apple_token_replays WHERE expires_at < ?").bind(now),
    env.DB
      .prepare("INSERT OR IGNORE INTO apple_token_replays (token_hash, expires_at) VALUES (?, ?)")
      .bind(identityTokenHash, tokenExpiresAt),
    env.DB
      .prepare(
        `INSERT OR IGNORE INTO accounts
         (id, apple_subject_hash, deletion_subject_hash, status, created_at, updated_at)
         SELECT ?, ?, ?, 'active', ?, ?
         WHERE NOT EXISTS (
           SELECT 1 FROM deletion_tombstones
           WHERE subject_hash = ? AND deleted_at >= ?
         )`,
      )
      .bind(
        candidateId,
        subjectHash,
        deletionSubjectHash,
        now,
        now,
        deletionSubjectHash,
        tokenIssuedAt,
      ),
    env.DB
      .prepare(
        `UPDATE accounts SET deletion_subject_hash = ?, updated_at = ?
         WHERE apple_subject_hash = ? AND status = 'active'`,
      )
      .bind(deletionSubjectHash, now, subjectHash),
    env.DB
      .prepare(
        `SELECT CASE WHEN EXISTS (
           SELECT 1 FROM deletion_tombstones
           WHERE subject_hash = ? AND deleted_at >= ?
         ) THEN 0 ELSE 1 END AS allowed`,
      )
      .bind(deletionSubjectHash, tokenIssuedAt),
  ]);

  if ((results[2]?.meta.changes ?? 0) !== 1) {
    throw authenticationFailed();
  }
  const guard = results[5]?.results[0] as { allowed?: number } | undefined;
  if (guard?.allowed !== 1) throw authenticationFailed();

  const row = await env.DB
    .prepare("SELECT id, status FROM accounts WHERE apple_subject_hash = ? LIMIT 1")
    .bind(subjectHash)
    .first<{ id: string; status: "active" | "disabled" }>();
  if (!row) throw new Error("account creation failed");
  if (row.status !== "active") {
    throw new AppError(403, "account_disabled", "This account has been deleted.");
  }

  const profile = await getAccountProfile(env.DB, row.id);
  if (!profile) throw new Error("account lookup failed");
  return profile;
}

export async function accountIdForAppleSubject(
  env: Env,
  appleSubject: string,
): Promise<string | null> {
  const subjectHash = await hmacSha256(env.APPLE_SUBJECT_PEPPER, appleSubject);
  const deletionSubjectHash = await hmacSha256(
    env.DELETION_TOMBSTONE_PEPPER,
    appleSubject,
  );
  const row = await env.DB
    .prepare(
      `UPDATE accounts SET deletion_subject_hash = ?, updated_at = ?
       WHERE apple_subject_hash = ? AND status = 'active'
       RETURNING id`,
    )
    .bind(deletionSubjectHash, Math.floor(Date.now() / 1000), subjectHash)
    .first<{ id: string }>();
  return row?.id ?? null;
}

export async function deleteAccountData(
  db: D1Database,
  accountId: string,
  now: number,
  snapshot: {
    expectedCredentialVersion: string | null;
    queuedAppleRevocation?: {
      id: string;
      ciphertext: string;
      nonce: string;
      createdAt: number;
      nextAttemptAt: number;
    };
  },
): Promise<boolean> {
  const credentialGuard = `(
    (? IS NULL AND NOT EXISTS (
      SELECT 1 FROM apple_credentials c WHERE c.account_id = accounts.id
    )) OR EXISTS (
      SELECT 1 FROM apple_credentials c
      WHERE c.account_id = accounts.id AND c.credential_version = ?
    )
  )`;
  const statements: D1PreparedStatement[] = [];
  if (snapshot.queuedAppleRevocation) {
    statements.push(
      db
        .prepare(
          `INSERT INTO apple_revocation_outbox
           (id, refresh_token_ciphertext, encryption_nonce,
            attempt_count, created_at, next_attempt_at)
           SELECT ?, ?, ?, 0, ?, ? FROM accounts
           WHERE id = ? AND status = 'active'
             AND deletion_subject_hash IS NOT NULL
             AND ${credentialGuard}`,
        )
        .bind(
          snapshot.queuedAppleRevocation.id,
          snapshot.queuedAppleRevocation.ciphertext,
          snapshot.queuedAppleRevocation.nonce,
          snapshot.queuedAppleRevocation.createdAt,
          snapshot.queuedAppleRevocation.nextAttemptAt,
          accountId,
          snapshot.expectedCredentialVersion,
          snapshot.expectedCredentialVersion,
        ),
    );
  }
  statements.push(
    db
      .prepare(
        `INSERT INTO deletion_tombstones (subject_hash, deleted_at)
         SELECT deletion_subject_hash, ?
         FROM accounts
         WHERE id = ? AND status = 'active'
           AND deletion_subject_hash IS NOT NULL
           AND ${credentialGuard}
         ON CONFLICT(subject_hash) DO UPDATE SET
           deleted_at = MAX(deletion_tombstones.deleted_at, excluded.deleted_at)`,
      )
      .bind(
        now,
        accountId,
        snapshot.expectedCredentialVersion,
        snapshot.expectedCredentialVersion,
      ),
    db
      .prepare(
        `DELETE FROM accounts
         WHERE id = ? AND status = 'active'
           AND deletion_subject_hash IS NOT NULL
           AND ${credentialGuard}`,
      )
      .bind(
        accountId,
        snapshot.expectedCredentialVersion,
        snapshot.expectedCredentialVersion,
      ),
  );
  const results = await db.batch(statements);
  return (results.at(-1)?.meta.changes ?? 0) > 0;
}

export async function pruneDeletionTombstones(
  db: D1Database,
  now = Math.floor(Date.now() / 1000),
): Promise<number> {
  const result = await db
    .prepare("DELETE FROM deletion_tombstones WHERE deleted_at < ?")
    .bind(now - DELETION_TOMBSTONE_SECONDS)
    .run();
  return result.meta.changes ?? 0;
}
