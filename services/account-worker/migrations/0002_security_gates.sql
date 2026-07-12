CREATE TABLE deletion_proofs (
  token_hash TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  consumed_at INTEGER
) STRICT;

CREATE INDEX deletion_proofs_account_id_idx ON deletion_proofs(account_id);

CREATE TABLE rate_limits (
  bucket TEXT NOT NULL,
  identifier_hash TEXT NOT NULL,
  window_start INTEGER NOT NULL,
  request_count INTEGER NOT NULL,
  PRIMARY KEY (bucket, identifier_hash, window_start)
) STRICT;

CREATE INDEX rate_limits_window_start_idx ON rate_limits(window_start);
