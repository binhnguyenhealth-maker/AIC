CREATE TABLE refresh_token_history (
  token_hash TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  used_at INTEGER NOT NULL
) STRICT;

CREATE INDEX refresh_token_history_session_id_idx ON refresh_token_history(session_id);
