import assert from "node:assert/strict";
import { afterEach, describe, it } from "node:test";
import type { Miniflare } from "miniflare";
import { AppError } from "../src/errors";
import { claimUsername, normalizeUsername, validateUsername } from "../src/usernames";
import { createTestDatabase, seedAccount } from "./helpers";

const instances: Miniflare[] = [];
afterEach(async () => {
  await Promise.all(instances.splice(0).map((instance) => instance.dispose()));
});

describe("username normalization and uniqueness", () => {
  it("normalizes NFKC, whitespace, and case", () => {
    assert.equal(normalizeUsername("  ＡｉＣ_１２３  "), "aic_123");
    assert.equal(validateUsername("  Cooked_User  "), "cooked_user");
  });

  it("rejects invalid and reserved usernames", () => {
    assert.throws(() => validateUsername("two words"), AppError);
    assert.throws(() => validateUsername("support"), AppError);
    assert.throws(() => validateUsername("f_u_c_k_you"), AppError);
    assert.throws(() => validateUsername("ab"), AppError);
  });

  it("enforces global uniqueness and idempotent same-account claims", async () => {
    const { mf, db } = await createTestDatabase();
    instances.push(mf);
    await seedAccount(db, "account-1");
    await seedAccount(db, "account-2");

    assert.equal(await claimUsername(db, "account-1", "Chi_User", 1_700_000_001), "chi_user");
    assert.equal(await claimUsername(db, "account-1", "chi_user", 1_700_000_002), "chi_user");
    await assert.rejects(
      claimUsername(db, "account-2", "CHI_USER", 1_700_000_003),
      (error: unknown) =>
        error instanceof AppError && error.status === 409 && error.code === "username_unavailable",
    );
  });
});
