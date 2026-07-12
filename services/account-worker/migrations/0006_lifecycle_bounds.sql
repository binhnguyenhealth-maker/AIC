ALTER TABLE accounts ADD COLUMN deletion_subject_hash TEXT;

CREATE UNIQUE INDEX accounts_deletion_subject_hash_idx
  ON accounts(deletion_subject_hash)
  WHERE deletion_subject_hash IS NOT NULL;

ALTER TABLE apple_credentials ADD COLUMN credential_version TEXT;

UPDATE apple_credentials
SET credential_version = lower(hex(randomblob(16)))
WHERE credential_version IS NULL;

CREATE UNIQUE INDEX apple_credentials_version_idx
  ON apple_credentials(credential_version)
  WHERE credential_version IS NOT NULL;

ALTER TABLE sessions ADD COLUMN absolute_expires_at INTEGER;

UPDATE sessions
SET absolute_expires_at = created_at + 7776000
WHERE absolute_expires_at IS NULL;

CREATE INDEX sessions_absolute_expiry_idx ON sessions(absolute_expires_at);

CREATE TABLE operational_counters (
  metric TEXT PRIMARY KEY,
  counter_value INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
) STRICT;
