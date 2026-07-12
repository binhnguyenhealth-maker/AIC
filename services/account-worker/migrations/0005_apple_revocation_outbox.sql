CREATE TABLE apple_revocation_outbox (
  id TEXT PRIMARY KEY,
  refresh_token_ciphertext TEXT NOT NULL,
  encryption_nonce TEXT NOT NULL,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  next_attempt_at INTEGER NOT NULL,
  last_attempt_at INTEGER
) STRICT;

CREATE INDEX apple_revocation_outbox_due_idx
  ON apple_revocation_outbox(next_attempt_at);
