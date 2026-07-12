import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { generateKeyPair, SignJWT } from "jose";
import { verifyAppleIdentityToken } from "../src/apple";
import { sha256 } from "../src/crypto";
import { AppError } from "../src/errors";

describe("Apple identity verification", () => {
  it("verifies signature, issuer, audience, expiry, age, and hashed nonce", async () => {
    const { privateKey, publicKey } = await generateKeyPair("RS256");
    const now = Math.floor(Date.now() / 1000);
    const rawNonce = "0123456789abcdef0123456789abcdef";
    const token = await new SignJWT({ nonce: await sha256(rawNonce) })
      .setProtectedHeader({ alg: "RS256", kid: "test-key" })
      .setSubject("apple-subject")
      .setIssuer("https://appleid.apple.com")
      .setAudience("com.binhnguyenhealth.aic")
      .setIssuedAt(now)
      .setExpirationTime(now + 300)
      .sign(privateKey);

    assert.deepEqual(
      await verifyAppleIdentityToken(
        token,
        rawNonce,
        "com.binhnguyenhealth.aic",
        () => publicKey,
      ),
      { subject: "apple-subject", issuedAt: now, expiresAt: now + 300 },
    );
    await assert.rejects(
      verifyAppleIdentityToken(
        token,
        "wrong-nonce-wrong-nonce",
        "com.binhnguyenhealth.aic",
        () => publicKey,
      ),
      (error: unknown) => error instanceof AppError && error.status === 401,
    );
    await assert.rejects(
      verifyAppleIdentityToken(token, rawNonce, "wrong.audience", () => publicKey),
      (error: unknown) => error instanceof AppError && error.status === 401,
    );
  });
});
