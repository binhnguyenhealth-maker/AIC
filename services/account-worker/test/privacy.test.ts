import assert from "node:assert/strict";
import { afterEach, describe, it } from "node:test";
import type { Miniflare } from "miniflare";
import { decryptAppleToken, encryptAppleToken } from "../src/crypto";
import { AppError } from "../src/errors";
import { readJsonObject } from "../src/http";
import { fetchHandler } from "../src/index";
import { logRequestFailure, redactForLog } from "../src/logging";
import type { Env } from "../src/types";
import { createTestDatabase } from "./helpers";

const instances: Miniflare[] = [];
afterEach(async () => {
  await Promise.all(instances.splice(0).map((instance) => instance.dispose()));
});

describe("privacy boundaries", () => {
  it("redacts authentication material and never logs tokens", () => {
    const jwt = "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.signature";
    const value = redactForLog({
      authorization: `Bearer ${jwt}`,
      identityToken: jwt,
      nested: { refresh_token: "opaque-refresh-secret", message: `failed Bearer ${jwt}` },
    });
    const serialized = JSON.stringify(value);
    assert.equal(serialized.includes(jwt), false);
    assert.equal(serialized.includes("opaque-refresh-secret"), false);

    const logged: unknown[][] = [];
    const originalConsoleError = console.error;
    console.error = (...args: unknown[]) => logged.push(args);
    try {
      logRequestFailure({
        event: "request_failed",
        requestId: "safe-request-id",
        status: 500,
        errorCode: "internal_error",
      });
    } finally {
      console.error = originalConsoleError;
    }
    assert.equal(logged.length, 1);
    assert.equal(
      logged[0]?.[0],
      '{"event":"request_failed","requestId":"safe-request-id","status":500,"errorCode":"internal_error"}',
    );
  });

  it("encrypts Apple refresh tokens with account-bound authenticated encryption", async () => {
    const key = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))));
    const encrypted = await encryptAppleToken("apple-refresh-token", key, "account-a");
    assert.equal(
      await decryptAppleToken(encrypted.ciphertext, encrypted.nonce, key, "account-a"),
      "apple-refresh-token",
    );
    await assert.rejects(
      decryptAppleToken(encrypted.ciphertext, encrypted.nonce, key, "account-b"),
    );
  });

  it("has no location or card endpoints and rejects geographic fields before Apple calls", async () => {
    const noEnv = {} as Env;
    for (const path of ["/v1/location", "/v1/cards", "/v1/receipts", "/v1/scans"]) {
      const response = await fetchHandler(new Request(`https://api.example.test${path}`), noEnv);
      assert.equal(response.status, 404);
    }

    const { mf, db } = await createTestDatabase();
    instances.push(mf);
    const response = await fetchHandler(
      new Request("https://api.example.test/v1/auth/apple/exchange", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          identityToken: "x".repeat(128),
          authorizationCode: "authorization-code",
          rawNonce: "raw-nonce-at-least-16",
          latitude: 41.88,
          longitude: -87.63,
          card: { neighborhood: "Loop" },
        }),
      }),
      {
        DB: db,
        RATE_LIMIT_PEPPER: "privacy-test-rate-limit-pepper-with-32-characters",
      } as Env,
    );
    assert.equal(response.status, 400);
    assert.doesNotMatch(await response.text(), /41\.88|-87\.63|Loop/u);
  });

  it("cancels a streaming body as soon as it exceeds 16 KiB", async () => {
    let cancelled = false;
    let emitted = 0;
    const stream = new ReadableStream<Uint8Array>({
      pull(controller) {
        emitted += 1;
        controller.enqueue(new Uint8Array(9_000));
      },
      cancel() {
        cancelled = true;
      },
    });
    const request = new Request(
      "https://api.example.test/v1/auth/refresh",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: stream,
        duplex: "half",
      } as RequestInit,
    );
    await assert.rejects(
      readJsonObject(request),
      (error: unknown) => error instanceof AppError && error.status === 413,
    );
    assert.equal(emitted, 2);
    assert.equal(cancelled, true);
  });

  it("rejects browser origins and emits no CORS permission", async () => {
    const response = await fetchHandler(
      new Request("https://api.example.test/v1/usernames/suggest", {
        method: "OPTIONS",
        headers: { Origin: "https://evil.example" },
      }),
      {} as Env,
    );
    assert.equal(response.status, 403);
    assert.equal(response.headers.get("access-control-allow-origin"), null);
  });
});
