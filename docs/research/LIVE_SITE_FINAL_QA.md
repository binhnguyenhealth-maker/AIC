# Live Site Final QA

**Audited revision:** `315e07ba2e7b6a09cd1eda760c7b42238e9f975a` (`main`)

**Audit date:** 2026-07-12 (America/New_York; HTTP observations were 2026-07-13 UTC)

**Live target:** `https://aic-beta-info.binhnguyenhealth.workers.dev`

**Scope:** The checked-in `web/public` surface, the read-only live deployment, support contact presentation, policy/methodology/status consistency, City of Chicago notice, stale-data disclosures, signed status bytes and response headers, and published links. No deployment, upload, push, form submission, email, Apple/Cloudflare account action, simulator action, or profile action was performed.

## Verdict

**NO-GO for final release sign-off.**

The deployment itself is healthy and exactly matches commit `315e07b`: every published HTML/CSS route and the status JSON returned `200` without redirects and was byte-identical to the corresponding checked-in file. Desktop and mobile rendering passed, all published HTTP links resolved, the signed status validated, and the public claims are internally consistent.

Final sign-off is still blocked because the repository and live Terms page do not reproduce the current official City notice exactly at the character level, and the required private support mailbox could not be proven deliverable/monitored under the prohibition on messaging anyone. The first issue needs a one-character source correction plus deployment/readback. The second needs an owner-authorized end-to-end inbox test.

## Blockers

| Severity | Blocker | Direct evidence | Exact closure |
| --- | --- | --- | --- |
| High | The City of Chicago notice is not character-exact against the current official notice. | On 2026-07-12, `https://www.chicago.gov/city/en/narr/foia/data_disclaimer.html` returned `200` and rendered `one’s own risk` with U+2019 RIGHT SINGLE QUOTATION MARK. `web/public/terms/index.html`, `DATA_SOURCES.md`, and `distribution/app-store/metadata/en-US/description.txt` use `one's own risk` with U+0027 APOSTROPHE. The live Terms response is byte-identical to the checked-in file, so it has the same mismatch. All other notice text matches. | Replace `one's own risk` with `one’s own risk` in all three source locations, deploy the public file, then re-fetch the official City page and live Terms page and require exact extracted-text equality. Preserve the rest of the prescribed notice unchanged. |
| Medium | End-to-end private support delivery and monitoring remain UNVERIFIED. | The live Support, Privacy, and Account Deletion pages expose `mailto:admin@holdmetoit.info`; `holdmetoit.info` has MX `1 smtp.google.com.`. No test email or mailbox/account inspection was performed because the task forbids messaging anyone and changing/accessing accounts. DNS and a `mailto:` link do not prove that this recipient exists, accepts mail, is monitored, or can reply. | With explicit owner authorization, send one non-sensitive test message from an unrelated mailbox to `admin@holdmetoit.info`, confirm receipt in the intended inbox, and confirm a reply can be sent. Retain the timestamp and redacted evidence; do not include secrets or personal content. |

## Route and byte verification

All routes were fetched with HTTPS `GET`, zero allowed redirects, bounded timeouts, separate response-header/body capture, SHA-256 hashing, and byte comparison against commit `315e07b`.

| Route | Status | Content type | Bytes | Live SHA-256 | Commit bytes |
| --- | ---: | --- | ---: | --- | --- |
| `/` | 200 | `text/html` | 857 | `7355dcb18fa9155da546d3b83d9cada86d8847775447538a6b4c144fe6bffc9c` | Equal |
| `/privacy/` | 200 | `text/html` | 3,838 | `7bdf16388f76b9cebd3e5f9337e17e38e2973a83005ee87d4b5a0aa5be58e1e6` | Equal |
| `/support/` | 200 | `text/html` | 2,751 | `2b98ad1cbb9f003a99cf579f35cef84e8108e373127d29b96738a5bd7925a014` | Equal |
| `/methodology/` | 200 | `text/html` | 4,629 | `1755d92c3a93b5edf51076d7e58dbab465af8d6ee9b5219588db49f638f924de` | Equal |
| `/terms/` | 200 | `text/html` | 2,808 | `b54c9c3473b1e367441213b3d27e7d6fbb7ef7f7cecc8b8eafb2299ab0a4b4ee` | Equal |
| `/account-deletion/` | 200 | `text/html` | 1,077 | `9f72c3078fa45bbcf50a7484fb70ca60017a08a80cc14c854465de84aec645b1` | Equal |
| `/styles.css` | 200 | `text/css` | 1,358 | `bf8d2d303c774003b036857454ddc7a01c01d293fddf93e29dbb943e69c6e30e` | Equal |
| `/pack-status/v1/status.json` | 200 | `application/json` | 759 | `13985f1463bcd6298dbfe231ecf1fdbf9d612a96cee7a00d5813b6d5a7161653` | Equal |

An intentionally missing route, `/__aic_qa_missing_315e07b`, returned an empty `404` without redirecting to a false-success page.

## Signed status JSON

The live 759-byte response is byte-identical to all three release copies:

- `web/public/pack-status/v1/status.json`
- `operations/pack-status/public/v1/status.json`
- `ios/AIC/Resources/pack_status_bootstrap.json`

The repository verifier accepted the live bytes and reported:

```text
AIC_PACK_STATUS_VALIDATION_OK
sequence=2
pack_sha256=1a18629fa3429eefec10d0d025c80102ce7c48a63457e601c1c404001686ca32
expires_at=2026-07-20T02:40:16Z
```

The decoded payload has schema version `1`, sequence `2`, the bundled pack marked `active`, and three signatures (`release-a`, `release-b`, `release-c`). Validation includes the pinned two-of-three Ed25519 threshold, bundled-pack SHA-256 match, active status, and at least 24 hours of remaining signed lifetime.

Observed `GET` response headers:

```text
HTTP/2 200
content-type: application/json
content-length: 759
cf-cache-status: HIT
cache-control: public, max-age=300, must-revalidate
etag: "92feec86fd001498d3a915433a501a98"
content-security-policy: default-src 'self'; style-src 'self'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'
cross-origin-opener-policy: same-origin
permissions-policy: camera=(), geolocation=(), microphone=(), payment=(), usb=()
referrer-policy: no-referrer
x-content-type-options: nosniff
x-frame-options: DENY
```

No `Set-Cookie`, redirect, `Content-Encoding`, query, or personalized response was observed. `HEAD` returned `200`; `If-None-Match` with the deployed ETag returned `304`; `POST` returned empty `405`. The five-minute HTTP cache does not extend the signed expiry.

**Operational time gate:** sequence 2 expires at `2026-07-20T02:40:16Z`. This was valid and outside the verifier's 24-hour stop window during QA, but it must be replaced by a reviewed higher sequence before expiry. A client with no still-valid verified status is designed to fail closed.

## Content consistency and stale-data disclosures

| Surface | Result | Evidence |
| --- | --- | --- |
| Landing page | Pass | Calls Cooked Score a historical index and explicitly says it is not a live safety assessment or personal-risk prediction. |
| Privacy | Pass | Describes on-device scan processing, no account data, Cloudflare's role, the fixed global status request, ordinary delivery metadata, and no cookies/analytics/personalization. No contradiction with the inspected client request or live response was found. |
| Support | Pass | Presents `admin@holdmetoit.info` as private support, warns against sending exact locations, explains that the historical window ends on the displayed source-through date, later records/revisions may be absent, the update-window cutoff fails closed, and a signed status can pause a flawed pack. |
| Methodology | Pass | Defines the 500-metre estimator, privacy-coarsened non-overlapping 250-metre cells, nearest-five category bands, within-Chicago comparison, estimated counts, and the limitations of preliminary reported-incident data. It says every score and receipt displays the exact source-through date and `not live`. |
| Terms | Pass except exact-character notice blocker | Describes preliminary, delayed, incomplete, revised, misclassified, and approximate records; prohibits safety/emergency/high-impact uses; and matches the no-account and on-device receipt scope. |
| Account deletion | Pass | Correctly states that guest-only v1 creates no AIC account data and explains deletion of local app data and third-party receipt copies. |
| Status/client behavior | Pass | `PackStatusClient` uses the configured fixed URL, `GET`, `Accept: application/json`, an ephemeral no-cookie session, no request body/query, a 15-minute refresh interval, signature/rollback checks, and fail-closed expiry behavior. |

The bundled manifest's current source-through date is `2026-06-30` and its local update-window cutoff is `2026-08-07`. Public pages do not falsely call the source current or real-time. They accurately distinguish the historical source-through date, the local update-window cutoff, and the separately signed remote-status expiry.

## Link and rendered-browser QA

All unique internal targets published in the HTML (`/`, `/privacy/`, `/support/`, `/methodology/`, `/terms/`, and `/styles.css`) returned the expected `200` content without redirects. The externally published GitHub issue tracker returned `200` at the exact URL without redirecting. The account-deletion route also returned `200`, although it is not linked from the landing-page navigation. No broken HTTP link was found.

Browser validation used the Codex in-app browser against the live deployment:

- Desktop viewport: `1440x900`.
- Mobile viewport: `390x844`.
- Every HTML route rendered a meaningful `h1`, its expected document title, and real page content.
- No horizontal overflow was detected at either inspected viewport.
- No framework error overlay, blank shell, console warning, or console error was observed.
- Interaction proof: clicked the unique landing-page `Support` link, observed navigation to `/support/`, and confirmed the rendered private-support email, stale-data disclosure, and fixed-global-status disclosure.
- Screenshots of the desktop and mobile landing page were visually inspected; text, navigation, borders, wrapping, and spacing were legible with no clipping or overlap.

## App Store / release field answers supported by this audit

These source-controlled values returned `200` and match the live deployment:

| Field | Exact value |
| --- | --- |
| Marketing URL | `https://aic-beta-info.binhnguyenhealth.workers.dev/` |
| Privacy Policy URL | `https://aic-beta-info.binhnguyenhealth.workers.dev/privacy/` |
| Support URL | `https://aic-beta-info.binhnguyenhealth.workers.dev/support/` |
| Private support contact shown on site | `admin@holdmetoit.info` |

This audit does **not** authorize or support an unconditional Content Rights attestation. The repository documents third-party City of Chicago data and continuing terms obligations; a qualified legal determination remains outside this engineering QA.

## Commands and checks performed

Key non-mutating checks included:

```sh
git status --short --branch
git rev-parse HEAD
git show -s 315e07b
git ls-tree -r --name-only 315e07b

curl --location --max-redirs 0 --dump-header <temp-header> \
  --output <temp-body> --write-out <route-metadata> <live-route>
shasum -a 256 <live-body> <checked-in-file>
cmp -s <live-body> <checked-in-file>

jq . <live-status.json>
jq -r .payload <live-status.json> | base64 -d | jq .
swift run --package-path ios AICPackStatusValidation \
  ios/AIC/Resources/chicago_beta.sqlite \
  ios/AIC/Resources/pack_status_bootstrap.json \
  <live-status.json>

curl --head <status-url>
curl -H 'If-None-Match: "92feec86fd001498d3a915433a501a98"' <status-url>
curl -X POST <status-url>

curl --location <official-City-notice-url>
curl --location <published-GitHub-issues-url>
dig +short MX holdmetoit.info
```

Browser checks covered page URL/title, DOM snapshot, meaningful-content check, overlay check, warning/error logs, desktop/mobile screenshot inspection, overflow measurements, all route identities, and the landing-page-to-Support interaction.

## Remaining UNVERIFIED items

- **Support mailbox delivery, ownership, monitoring, and reply path:** blocked by the explicit prohibition on messaging anyone or accessing/changing accounts.
- **Corrected City notice deployment/readback:** no source correction or deployment was authorized in this report-only audit.
- **Status behavior after `2026-07-20T02:40:16Z`:** the current artifact is valid now; a future higher-sequence issuance and its deployment are not yet available to verify.
- **Multi-region CDN equality:** responses were observed through Cloudflare's DFW edge only. Other regions were not forced or sampled.
- **Safari/Firefox and additional responsive breakpoints:** browser QA covered the in-app Chromium surface at one desktop and one mobile viewport.
- **Apple/App Store Connect fields and processed-build URL behavior:** no Apple account or App Store Connect surface was accessed.
- **Cloudflare account/origin configuration and log-retention settings:** only public response behavior was inspected; no Cloudflare account was accessed.
- **Legal sufficiency and external statistical review:** neither is established by this engineering QA.

## Release recommendation

Do not treat the live-site gate as closed yet. First make the one-character City-notice correction consistently in Terms, the App Store description, and `DATA_SOURCES.md`; deploy and prove exact readback. Separately, have the mailbox owner perform a redacted end-to-end test of `admin@holdmetoit.info`. After both items are evidenced, rerun the route/hash/status checks and sign off only if the status artifact still has adequate lifetime.
