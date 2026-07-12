# AIC account Worker

Minimal native-iOS account service for the Chicago beta. It has no scan, location,
receipt, card, analytics, or history endpoints.

## Security and privacy boundary

- Native-app-only API: requests with an `Origin` header are rejected and responses
  never include CORS allow headers.
- Sign in with Apple identity tokens are verified against Apple's rotating JWKS with
  pinned `RS256`, issuer, audience, expiry, issued-at age, subject, and hashed nonce.
- The single-use Apple authorization code is validated at `/auth/token`; the returned
  identity token must match the original subject and nonce.
- Every newly acquired Apple refresh token is first encrypted under a random outbox ID
  and durably staged before account lookup or reauthentication matching. Promotion into
  `apple_credentials` and removal of that staged copy occur in one active-account-guarded
  D1 batch. When promotion replaces a distinct existing credential, that displaced token
  is first re-encrypted under a new random outbox ID and queued in the same batch. If
  deletion wins or overlaps either transition, every acquired or displaced token remains
  queued for revocation and no AIC session or deletion proof is released from a losing
  transition.
- Apple's refresh token is encrypted with AES-256-GCM and account-ID additional
  authenticated data while the account exists. A separate encryption key is required
  in every environment.
- AIC refresh tokens are opaque 256-bit values, stored only as SHA-256 hashes, and
  rotated on every refresh. Reuse of a rotated token revokes the current token family.
  Refresh is bounded both per edge IP and per account/session family. A session is
  revoked and requires fresh Sign in with Apple after 2,048 rotations, which also hard
  bounds its refresh-history cardinality. Access tokens last 15 minutes; refresh tokens
  slide up to 30 days but every session
  has a non-renewable 90-day absolute lifetime. Scheduled cleanup deletes expired and
  old revoked sessions; refresh history cascades with its bounded parent session.
- Logout is effective immediately because every authenticated request rechecks D1.
- Account deletion requires a new Sign in with Apple proof and an account-bound,
  one-time deletion token that expires after five minutes. The proof is consumed before
  a credential-version-guarded D1 transaction records the tombstone, optionally queues
  revocation, and hard-deletes the account, public username, credential, proof, sessions,
  and refresh history through foreign-key cascades. No disabled intermediate account can
  be stranded by network interruption.
- Local deletion does not depend on Apple's availability. When the credential is
  decryptable, its token is always re-encrypted under a random outbox ID and queued in
  the same transaction before any Apple network call. Revocation is then attempted as
  best-effort background work; a 15-minute scheduled handler retries failures. Outbox
  `created_at` is hour-bucketed and first retry is jittered so it cannot be joined to the
  exact tombstone timestamp. Ciphertext is deleted on success or after 20 attempts / 30
  days. Exhaustion increments only a token-free aggregate D1 counter. The outbox stores
  no account ID, subject hash, username, or per-item failure text.
- If a retained Apple credential cannot decrypt, deletion fails closed while the account
  and encrypted credential remain intact; it never hard-deletes the only remaining
  revocation capability.
- The application logger emits only a closed 5xx record containing event, request ID,
  status, and error code. It never receives request headers, bodies, thrown errors, or tokens.
- All responses use `Cache-Control: no-store`; Worker observability is off by default.
- D1 fixed-window limits protect Apple exchange (10/5 minutes/IP), Apple reauth
  (5/10 minutes/account), refresh (20/5 minutes/IP), username suggestion
  (30/minute/account), and username claim (10/10 minutes/account). Exchange and refresh
  limits run before reading the body. Valid refresh families have an additional
  12/5-minute account/session bucket, preventing multi-IP bypass. IP/account/session
  identifiers are HMACed before storage.
- JSON bodies are streamed and cancelled immediately after crossing the 16 KiB limit.

Deletion temporarily retains only `{HMAC(Apple subject), deleted_at}` as a tombstone.
Its HMAC uses `DELETION_TOMBSTONE_PEPPER`, a secret distinct from the active-account
subject pepper. It contains no username, account ID, Apple token, or profile data and is
used only to reject an Apple identity token issued at or before deletion. A genuinely
fresh later Apple sign-in may create a distinct account ID with no revived username or
data. Tombstones are pruned after 24 hours during sign-in and scheduled maintenance;
Apple tokens older than 10
minutes are rejected independently.

## API contract

All request bodies are JSON and unknown fields are rejected. Authenticated routes use
`Authorization: Bearer <accessToken>`. Errors have this stable shape:

```json
{
  "error": {
    "code": "invalid_request",
    "message": "Request contains unsupported fields.",
    "requestId": "opaque-id"
  }
}
```

### `GET /health`

Returns `200 {"status":"ok"}`. This is the only unauthenticated non-Apple route.

### `POST /v1/auth/apple/exchange`

The iOS app generates a raw random nonce, puts its SHA-256 value on the
`ASAuthorizationAppleIDRequest`, and sends the original raw value here.

```json
{
  "identityToken": "<Apple JWT>",
  "authorizationCode": "<one-time Apple code>",
  "rawNonce": "<original nonce>"
}
```

Success response:

```json
{
  "account": { "id": "UUID", "username": null, "status": "active" },
  "accessToken": "opaque-to-the-client JWT",
  "accessTokenExpiresIn": 900,
  "refreshToken": "opaque refresh token",
  "refreshTokenExpiresIn": 2592000
}
```

### `POST /v1/auth/refresh`

Request: `{"refreshToken":"..."}`. Returns the same shape as Apple exchange with a
new access token and rotated refresh token. Near the absolute session deadline,
`refreshTokenExpiresIn` is shorter than 30 days. The old refresh token becomes invalid.
Presenting a previously rotated token revokes the current refresh-token family.
At 2,048 rotations the family is revoked and the endpoint returns
`fresh_apple_sign_in_required`.

### `POST /v1/auth/apple/reauth`

Authenticated. Requires the same `identityToken`, `authorizationCode`, and `rawNonce`
fields as initial exchange. Apple validation must resolve to the bearer account. Returns:

```json
{ "reauthToken": "opaque one-time token", "expiresIn": 300 }
```

Only the SHA-256 hash is stored. A new proof replaces older proofs for the account.

### `GET /v1/account`

Authenticated. Returns `{"account":{"id":"UUID","username":"name-or-null","status":"active"}}`.

### `POST /v1/usernames/suggest`

Authenticated. Request `{}` or `{"preferredBase":"Bin"}`. Returns an advisory,
race-prone suggestion such as `{"username":"bin_x7k2p","available":true}`; claim is
the authoritative uniqueness check.

### `PUT /v1/usernames/claim`

Authenticated. Request `{"username":"bin_x7k2p"}`. Returns the normalized username.
Usernames are NFKC-normalized, lowercase ASCII `[a-z0-9_]`, 3–20 characters, globally
unique, and protected by a starter reserved-name list. This endpoint is first-claim-only
and idempotent when the same account repeats the same username.

### `POST /v1/auth/logout`

Authenticated. Requires an empty JSON body `{}` and returns `204` after revoking the
current session.

### `DELETE /v1/account`

Authenticated. Request
`{"confirmation":"DELETE","reauthToken":"<fresh one-time proof>"}` and returns `204`
after proof consumption and local hard deletion. If Apple is unavailable, the response
still succeeds after the encrypted revocation item is atomically queued for retry.
The local transaction completes before any `/auth/revoke` request begins.

## Manual Apple and Cloudflare setup

No external resource was created or deployed by this package.

1. Confirm that App ID / bundle ID `com.binhnguyenhealth.aic` is available in the
   founder's Apple Developer team, register it, and enable Sign in with Apple. The value
   in `APPLE_AUDIENCE` is provisional until that is complete.
2. Create a Sign in with Apple `.p8` key and record its Key ID and Team ID.
3. Create separate D1 databases for development, staging, and production. Replace the
   placeholder database ID in each Wrangler environment and apply all files under `migrations/`.
   Confirm the `*/15 * * * *` scheduled trigger is enabled for revocation retries.
4. Set non-secret variables per environment: `APPLE_AUDIENCE`, `APPLE_TEAM_ID`,
   `APPLE_KEY_ID`, `TOKEN_ISSUER` (the real HTTPS API origin), and `TOKEN_AUDIENCE`.
5. Store these only with `wrangler secret put` (never in Wrangler config or Git):
   - `APPLE_PRIVATE_KEY`: complete PKCS#8 `.p8` content.
   - `APPLE_TOKEN_ENCRYPTION_KEY`: base64 of exactly 32 random bytes.
   - `APPLE_SUBJECT_PEPPER`: at least 32 random characters.
   - `DELETION_TOMBSTONE_PEPPER`: a distinct secret of at least 32 random characters.
   - `ACCESS_TOKEN_SECRET`: at least 32 random characters.
   - `RATE_LIMIT_PEPPER`: at least 32 random characters.
6. Confirm the iOS entitlement, App ID, provisioning profile, and Worker audience all
   use the exact same bundle identifier before enabling real sign-in.

Apple's relevant primary documentation: [token validation](https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens),
[token revocation](https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens),
and [TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple).

## Local verification

```bash
npm install
npm run typecheck
npm test
npm run db:migrate:local
```

The founder's workspace path contains a literal `?`, which Vite/esbuild interpret as a
URL query. `npm test` therefore copies the exact package source into a temporary safe
path, runs the Node test suites there, and removes that temporary directory afterward.
It does not alter tracked source.
