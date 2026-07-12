import assert from "node:assert/strict";
import { afterEach, describe, it } from "node:test";
import type { Miniflare } from "miniflare";
import { AppError } from "../src/errors";
import { fetchHandler } from "../src/index";
import { enforceRateLimit, RATE_LIMITS } from "../src/rate-limit";
import type { Env } from "../src/types";
import { createTestDatabase } from "./helpers";

const instances: Miniflare[] = [];
afterEach(async () => {
  await Promise.all(instances.splice(0).map((instance) => instance.dispose()));
});

describe("rate limits", () => {
  it("enforces deterministic per-identifier fixed windows without storing the identifier", async () => {
    const { mf, db } = await createTestDatabase();
    instances.push(mf);
    const pepper = "rate-limit-test-pepper-with-32-plus-characters";
    const rule = { bucket: "test", limit: 2, windowSeconds: 60 };
    const now = 1_700_000_010;

    await enforceRateLimit(db, pepper, rule, "203.0.113.7", now);
    await enforceRateLimit(db, pepper, rule, "203.0.113.7", now + 1);
    await assert.rejects(
      enforceRateLimit(db, pepper, rule, "203.0.113.7", now + 2),
      (error: unknown) => error instanceof AppError && error.status === 429,
    );
    await enforceRateLimit(db, pepper, rule, "203.0.113.8", now + 2);
    await enforceRateLimit(db, pepper, rule, "203.0.113.7", now + 60);

    const rows = await db
      .prepare("SELECT identifier_hash FROM rate_limits")
      .all<{ identifier_hash: string }>();
    assert.equal(rows.results.some((row) => row.identifier_hash.includes("203.0.113")), false);
  });

  it("bounds refresh attempts per edge IP", async () => {
    const { mf, db } = await createTestDatabase();
    instances.push(mf);
    const pepper = "rate-limit-test-pepper-with-32-plus-characters";
    const now = 1_700_000_000;
    for (let attempt = 0; attempt < RATE_LIMITS.sessionRefresh.limit; attempt += 1) {
      await enforceRateLimit(
        db,
        pepper,
        RATE_LIMITS.sessionRefresh,
        "203.0.113.9",
        now,
      );
    }
    await assert.rejects(
      enforceRateLimit(
        db,
        pepper,
        RATE_LIMITS.sessionRefresh,
        "203.0.113.9",
        now,
      ),
      (error: unknown) => error instanceof AppError && error.status === 429,
    );
    await enforceRateLimit(
      db,
      pepper,
      RATE_LIMITS.sessionRefresh,
      "203.0.113.10",
      now,
    );
  });

  it("rejects saturated exchange and refresh buckets before accessing request bodies", async () => {
    const { mf, db } = await createTestDatabase();
    instances.push(mf);
    const pepper = "rate-limit-test-pepper-with-32-plus-characters";
    const now = Math.floor(Date.now() / 1000);
    for (const rule of [RATE_LIMITS.appleExchange, RATE_LIMITS.sessionRefresh]) {
      for (let attempt = 0; attempt < rule.limit; attempt += 1) {
        await enforceRateLimit(db, pepper, rule, "missing-edge-client-ip", now);
      }
    }

    for (const path of ["/v1/auth/apple/exchange", "/v1/auth/refresh"]) {
      let bodyAccessed = false;
      const request = {
        method: "POST",
        url: `https://api.example.test${path}`,
        headers: new Headers({ "Content-Type": "application/json" }),
        get body(): never {
          bodyAccessed = true;
          throw new Error("body must not be accessed");
        },
      } as unknown as Request;
      const response = await fetchHandler(
        request,
        { DB: db, RATE_LIMIT_PEPPER: pepper } as Env,
      );
      assert.equal(response.status, 429);
      assert.equal(bodyAccessed, false);
    }
  });
});
