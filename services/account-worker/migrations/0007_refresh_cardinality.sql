ALTER TABLE sessions ADD COLUMN rotation_count INTEGER NOT NULL DEFAULT 0;

UPDATE sessions
SET rotation_count = (
  SELECT COUNT(*) FROM refresh_token_history h WHERE h.session_id = sessions.id
);

CREATE INDEX sessions_rotation_count_idx ON sessions(rotation_count);
