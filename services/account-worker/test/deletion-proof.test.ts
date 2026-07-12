import assert from "node:assert/strict";
import { afterEach, describe, it } from "node:test";
import type { Miniflare } from "miniflare";
import { consumeDeletionProof, issueDeletionProof } from "../src/deletion-proof";
import { AppError } from "../src/errors";
import { createTestDatabase, seedAccount } from "./helpers";

const instances: Miniflare[] = [];
afterEach(async () => {
  await Promise.all(instances.splice(0).map((instance) => instance.dispose()));
});

describe("fresh deletion proof", () => {
  it("is account-bound, five-minute, one-time, and stored only as a hash", async () => {
    const { mf, db } = await createTestDatabase();
    instances.push(mf);
    await seedAccount(db, "account-proof");
    await seedAccount(db, "account-other");
    const now = 1_700_000_000;
    const proof = await issueDeletionProof(db, "account-proof", now);
    const stored = await db
      .prepare("SELECT token_hash, expires_at FROM deletion_proofs WHERE account_id = ?")
      .bind("account-proof")
      .first<{ token_hash: string; expires_at: number }>();
    assert.ok(stored);
    assert.notEqual(stored.token_hash, proof);
    assert.equal(stored.expires_at, now + 300);

    await assert.rejects(
      consumeDeletionProof(db, "account-other", proof, now + 1),
      (error: unknown) => error instanceof AppError && error.code === "recent_authentication_required",
    );
    await consumeDeletionProof(db, "account-proof", proof, now + 1);
    await assert.rejects(consumeDeletionProof(db, "account-proof", proof, now + 2));

    const expired = await issueDeletionProof(db, "account-proof", now);
    await assert.rejects(consumeDeletionProof(db, "account-proof", expired, now + 301));
  });
});
