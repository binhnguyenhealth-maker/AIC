import assert from "node:assert/strict";
import { afterEach, describe, it } from "node:test";
import type { Miniflare } from "miniflare";
import {
  authenticate,
  createSession,
  pruneExpiredSessions,
  REVOKED_SESSION_RETENTION_SECONDS,
  rotateRefreshToken,
  SESSION_ABSOLUTE_SECONDS,
} from "../src/sessions";
import { fetchHandler } from "../src/index";
import type { Env } from "../src/types";
import { createTestDatabase, seedAccount } from "./helpers";

const instances: Miniflare[] = [];
afterEach(async () => {
  await Promise.all(instances.splice(0).map((instance) => instance.dispose()));
});

describe("session lifecycle", () => {
  it("hashes refresh tokens, rotates them atomically, and immediately enforces revocation", async () => {
    const { mf, db } = await createTestDatabase();
    instances.push(mf);
    const accountId = "account-session";
    const now = Math.floor(Date.now() / 1000);
    await seedAccount(db, accountId, now);
    const env = {
      DB: db,
      ACCESS_TOKEN_SECRET: "test-access-secret-with-more-than-32-characters",
      TOKEN_ISSUER: "https://api.example.test",
      TOKEN_AUDIENCE: "aic-ios",
      RATE_LIMIT_PEPPER: "test-rate-limit-pepper-with-more-than-32-characters",
    } as Env;

    const first = await createSession(env, accountId, now);
    const stored = await db
      .prepare(
        "SELECT id, refresh_token_hash, absolute_expires_at FROM sessions WHERE account_id = ?",
      )
      .bind(accountId)
      .first<{ id: string; refresh_token_hash: string; absolute_expires_at: number }>();
    assert.ok(stored);
    assert.notEqual(stored.refresh_token_hash, first.refreshToken);
    assert.equal(stored.absolute_expires_at, now + SESSION_ABSOLUTE_SECONDS);

    const firstRequest = new Request("https://api.example.test/v1/usernames/suggest", {
      headers: { Authorization: `Bearer ${first.accessToken}` },
    });
    assert.equal((await authenticate(firstRequest, env)).accountId, accountId);
    const accountResponse = await fetchHandler(
      new Request("https://api.example.test/v1/account", {
        headers: { Authorization: `Bearer ${first.accessToken}` },
      }),
      env,
    );
    assert.equal(accountResponse.status, 200);
    assert.deepEqual(await accountResponse.json(), {
      account: { id: accountId, username: null, status: "active" },
    });

    const rotated = await rotateRefreshToken(env, first.refreshToken, now + 1);
    assert.notEqual(rotated.session.refreshToken, first.refreshToken);
    await assert.rejects(rotateRefreshToken(env, first.refreshToken, now + 2));
    await assert.rejects(rotateRefreshToken(env, rotated.session.refreshToken, now + 3));
    const history = await db
      .prepare("SELECT token_hash FROM refresh_token_history WHERE session_id = ?")
      .bind(stored.id)
      .first<{ token_hash: string }>();
    assert.ok(history);
    assert.notEqual(history.token_hash, first.refreshToken);

    const rotatedRequest = new Request("https://api.example.test/v1/usernames/suggest", {
      headers: { Authorization: `Bearer ${rotated.session.accessToken}` },
    });
    await assert.rejects(authenticate(rotatedRequest, env));
  });

  it("enforces absolute lifetime and prunes sessions with their refresh history", async () => {
    const { mf, db } = await createTestDatabase();
    instances.push(mf);
    const now = Math.floor(Date.now() / 1000);
    await seedAccount(db, "account-expiry", now);
    const env = {
      DB: db,
      ACCESS_TOKEN_SECRET: "test-access-secret-with-more-than-32-characters",
      TOKEN_ISSUER: "https://api.example.test",
      TOKEN_AUDIENCE: "aic-ios",
      RATE_LIMIT_PEPPER: "test-rate-limit-pepper-with-more-than-32-characters",
    } as Env;

    const expiring = await createSession(env, "account-expiry", now);
    await assert.rejects(
      rotateRefreshToken(env, expiring.refreshToken, now + SESSION_ABSOLUTE_SECONDS),
    );

    const active = await createSession(env, "account-expiry", now + 1);
    await rotateRefreshToken(env, active.refreshToken, now + 2);
    const activeRow = await db
      .prepare("SELECT id FROM sessions WHERE refresh_token_hash IS NOT NULL ORDER BY created_at DESC")
      .first<{ id: string }>();
    assert.ok(activeRow);
    await db
      .prepare("UPDATE sessions SET revoked_at = ?, absolute_expires_at = ? WHERE id = ?")
      .bind(
        now - REVOKED_SESSION_RETENTION_SECONDS,
        now + SESSION_ABSOLUTE_SECONDS,
        activeRow.id,
      )
      .run();

    assert.equal(await pruneExpiredSessions(db, now), 1);
    assert.equal(
      await db.prepare("SELECT id FROM sessions WHERE id = ?").bind(activeRow.id).first(),
      null,
    );
    assert.equal(
      await db
        .prepare("SELECT token_hash FROM refresh_token_history WHERE session_id = ?")
        .bind(activeRow.id)
        .first(),
      null,
    );
  });
});
