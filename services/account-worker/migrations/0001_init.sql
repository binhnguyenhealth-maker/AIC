CREATE TABLE accounts (
  id TEXT PRIMARY KEY,
  apple_subject_hash TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled')),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  disabled_at INTEGER
) STRICT;

CREATE TABLE usernames (
  account_id TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  normalized TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
) STRICT;

CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  refresh_token_hash TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  revoked_at INTEGER
) STRICT;

CREATE INDEX sessions_account_id_idx ON sessions(account_id);
CREATE INDEX sessions_expiry_idx ON sessions(expires_at);

CREATE TABLE apple_token_replays (
  token_hash TEXT PRIMARY KEY,
  expires_at INTEGER NOT NULL
) STRICT;

CREATE INDEX apple_token_replays_expiry_idx ON apple_token_replays(expires_at);

CREATE TABLE apple_credentials (
  account_id TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  refresh_token_ciphertext TEXT NOT NULL,
  encryption_nonce TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
) STRICT;
