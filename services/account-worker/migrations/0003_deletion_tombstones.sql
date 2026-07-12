CREATE TABLE deletion_tombstones (
  subject_hash TEXT PRIMARY KEY,
  deleted_at INTEGER NOT NULL
) STRICT;

CREATE INDEX deletion_tombstones_deleted_at_idx ON deletion_tombstones(deleted_at);
