import { AppError, badRequest } from "./errors";

const USERNAME_PATTERN = /^[a-z0-9_]{3,20}$/u;
const RESERVED = new Set([
  "admin",
  "aic",
  "api",
  "cooked",
  "help",
  "moderator",
  "null",
  "root",
  "security",
  "staff",
  "support",
  "undefined",
  "www",
]);
const PROFANE_FRAGMENTS = ["bitch", "cunt", "dick", "fuck", "nazi", "pussy", "shit", "slut", "whore"];

export function normalizeUsername(input: string): string {
  return input.normalize("NFKC").trim().toLowerCase();
}

export function validateUsername(input: string): string {
  const normalized = normalizeUsername(input);
  if (!USERNAME_PATTERN.test(normalized)) {
    throw badRequest(
      "invalid_username",
      "Username must be 3–20 lowercase letters, numbers, or underscores.",
    );
  }
  if (RESERVED.has(normalized)) {
    throw badRequest("invalid_username", "That username is unavailable.");
  }
  const compact = normalized.replaceAll("_", "");
  if (PROFANE_FRAGMENTS.some((fragment) => compact.includes(fragment))) {
    throw badRequest("invalid_username", "That username is unavailable.");
  }
  return normalized;
}

function suggestionBase(preferredBase?: string): string {
  const normalized = (preferredBase ?? "")
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[^a-z0-9_]+/gu, "_")
    .replace(/_+/gu, "_")
    .replace(/^_+|_+$/gu, "")
    .slice(0, 14);
  if (normalized.length < 3 || RESERVED.has(normalized)) return "cooked";
  return normalized;
}

function randomSuffix(length = 5): string {
  const alphabet = "abcdefghjkmnpqrstuvwxyz23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  return [...bytes].map((byte) => alphabet[byte % alphabet.length]).join("");
}

async function isAvailable(db: D1Database, username: string): Promise<boolean> {
  const row = await db
    .prepare("SELECT 1 AS found FROM usernames WHERE normalized = ? LIMIT 1")
    .bind(username)
    .first<{ found: number }>();
  return row === null;
}

export async function suggestUsername(db: D1Database, preferredBase?: string): Promise<string> {
  const base = suggestionBase(preferredBase);
  if (base !== "cooked" && (await isAvailable(db, base))) return base;

  for (let attempt = 0; attempt < 10; attempt += 1) {
    const candidate = `${base}_${randomSuffix()}`.slice(0, 20);
    if (await isAvailable(db, candidate)) return candidate;
  }
  throw new AppError(503, "username_suggestion_unavailable", "Try again in a moment.");
}

export async function claimUsername(
  db: D1Database,
  accountId: string,
  input: string,
  now: number,
): Promise<string> {
  const normalized = validateUsername(input);
  const existing = await db
    .prepare("SELECT normalized FROM usernames WHERE account_id = ? LIMIT 1")
    .bind(accountId)
    .first<{ normalized: string }>();

  if (existing) {
    if (existing.normalized === normalized) return normalized;
    throw new AppError(409, "username_already_claimed", "This account already has a username.");
  }

  try {
    await db
      .prepare(
        "INSERT INTO usernames (account_id, normalized, created_at, updated_at) VALUES (?, ?, ?, ?)",
      )
      .bind(accountId, normalized, now, now)
      .run();
  } catch {
    const own = await db
      .prepare("SELECT normalized FROM usernames WHERE account_id = ? LIMIT 1")
      .bind(accountId)
      .first<{ normalized: string }>();
    if (own?.normalized === normalized) return normalized;
    throw new AppError(409, "username_unavailable", "That username is unavailable.");
  }
  return normalized;
}
