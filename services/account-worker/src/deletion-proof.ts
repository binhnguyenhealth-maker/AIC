import { randomToken, sha256 } from "./crypto";
import { AppError, authenticationFailed } from "./errors";

export const DELETION_PROOF_SECONDS = 5 * 60;

function recentAuthenticationRequired(): AppError {
  return new AppError(
    401,
    "recent_authentication_required",
    "Sign in with Apple again to delete your account.",
  );
}

export async function issueDeletionProof(
  db: D1Database,
  accountId: string,
  now: number,
): Promise<string> {
  const token = randomToken();
  const tokenHash = await sha256(token);
  const results = await db.batch([
    db.prepare("DELETE FROM deletion_proofs WHERE account_id = ?").bind(accountId),
    db
      .prepare(
        `INSERT INTO deletion_proofs
         (token_hash, account_id, created_at, expires_at)
         SELECT ?, id, ?, ? FROM accounts
         WHERE id = ? AND status = 'active'`,
      )
      .bind(tokenHash, now, now + DELETION_PROOF_SECONDS, accountId),
  ]);
  if ((results[1]?.meta.changes ?? 0) !== 1) throw authenticationFailed();
  return token;
}

export async function consumeDeletionProof(
  db: D1Database,
  accountId: string,
  token: string,
  now: number,
): Promise<void> {
  if (token.length < 40 || token.length > 128) throw recentAuthenticationRequired();
  const tokenHash = await sha256(token);
  const result = await db
    .prepare(
      `UPDATE deletion_proofs
       SET consumed_at = ?
       WHERE token_hash = ? AND account_id = ?
         AND consumed_at IS NULL AND expires_at > ?`,
    )
    .bind(now, tokenHash, accountId, now)
    .run();
  if ((result.meta.changes ?? 0) !== 1) throw recentAuthenticationRequired();
}
