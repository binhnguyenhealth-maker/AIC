export interface Env {
  DB: D1Database;
  APPLE_AUDIENCE: string;
  APPLE_TEAM_ID: string;
  APPLE_KEY_ID: string;
  APPLE_PRIVATE_KEY: string;
  APPLE_TOKEN_ENCRYPTION_KEY: string;
  RATE_LIMIT_PEPPER: string;
  ACCESS_TOKEN_SECRET: string;
  APPLE_SUBJECT_PEPPER: string;
  DELETION_TOMBSTONE_PEPPER: string;
  TOKEN_ISSUER: string;
  TOKEN_AUDIENCE: string;
}

export interface AccountProfile {
  id: string;
  username: string | null;
  status: "active" | "disabled";
}

export interface AuthContext {
  accountId: string;
  sessionId: string;
}
