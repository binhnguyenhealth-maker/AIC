# Final release-diff audit 2

**Audited range:** `0446c4b739cb23a247f537cdcee09538f523a433..315e07ba2e7b6a09cd1eda760c7b42238e9f975a` (`origin/main` through release-candidate commit `315e07b`)

**Audit date:** 2026-07-12 (America/New_York; live checks continued after 00:00 UTC)

**Verdict:** **NO-GO for upload, TestFlight distribution, or App Review submission.**

The candidate is substantially improved: Release is operationally guest-only, the signed IPA has no Sign in with Apple entitlement or account endpoint, the refreshed Chicago pack is internally consistent, local freshness blocks at `2026-08-07T00:00:00Z`, the live policy pages match the repository, the screenshots and copy are coherent, and the live signed status file authorizes the exact bundled pack. It is not launch-ready because the emergency-status operational gate is not actually closed, the signed binary contradicts the claimed account-free binary inspection, final device states and the exact post-fix signed artifact are unproved, and required Apple/legal/statistical gates remain open.

This is an engineering release audit, not legal advice. No deployment, upload, push, submission, account mutation, message, or simulator/profile action was performed.

## Blocker table

| Severity | Finding | Direct evidence | Required closure |
| --- | --- | --- | --- |
| **High** | **The emergency pack-status service will fail closed globally on 2026-07-20, but no monitored renewal control or end-to-end operational drill is evidenced.** | The live URL, bundled bootstrap, and checked-in public object are byte-identical SHA-256 `13985f...1653`. Their signed sequence-2 payload expires at `2026-07-20T02:40:16Z`. `operations/pack-status/README.md:32-34` states that deadline. `.github/workflows/ci.yml:3-7` runs only on push, PR, or manual dispatch—there is no schedule. `distribution/app-store/submission-checklist.md:43` nevertheless marks the emergency correction/withdrawal path established and tested. The only app-hosted status tests (`ios/Tests/AICAppTests/PackStatusClientTests.swift`) verify the bundled signature and request shape; they do not exercise network renewal, persistence, omission, withdrawal, or expired-cache behavior. No repository evidence records a deployed withdrawal/renewal drill, owner, alert, or response receipt. | Before any distribution, assign a named primary and backup owner; create an independent daily expiry monitor with paging well before 48 hours remaining; document two-of-three key custody and renewal availability; issue and deploy a higher sequence on a recurring cadence shorter than the seven-day lifetime; read back and verify exact bytes from an unrelated network; and retain a dated renewal receipt. Add injectable client tests for active renewal, withdrawn pack, omitted pack, bad signature, expired cache, store failure, and recovery with a higher sequence. Correct checklist line 43 until an end-to-end drill is evidenced. |
| **High** | **Required launch and attestation gates remain explicitly open.** | `distribution/app-store/submission-checklist.md:26-36` leaves the App Store Connect record, review contacts, agreement/tax/banking clearance, upload/processing, TestFlight install, physical-device smoke test, forms, final screenshots, and submission open. Lines 40-45 leave independent statistical review, qualified legal/privacy review, final-device freshness-state validation, and pack-refresh ownership open. Apple requires complete review contact details and an accurate demo-account answer; the current guest-only answer is “sign-in not required / no demo account.” | Do not upload or submit until the account holder completes these gates. The founder/counsel must make the content-rights, legal, DSA, and storefront decisions; this audit cannot make those attestations. After fixes, create a new signed archive/IPA, install the processed TestFlight build on a physical iPhone, exercise clean launch, both location paths, receipt sharing/cancel, foreground status refresh, offline cached status, update-due-soon, withdrawn/omitted status in a controlled test build, and scans-paused at the local cutoff. |
| **Medium** | **The signed IPA contains dormant public-username receipt UI/copy, contradicting the release evidence and the “no public-username feature” policy wording.** | `ReceiptScreen` always compiles `username`, `showUsername`, the username toggle, and account-linked copy (`ios/AIC/Features/Receipt/ReceiptScreen.swift:4-27,42-54`). Release makes the path unreachable only because `AppModel.username` is always empty (`ios/AIC/App/AppModel.swift:128-140`). Direct `strings` inspection of signed IPA SHA-256 `0b51e2...2a23` found: `This receipt links your public username ...`. This contradicts `docs/research/GUEST_ONLY_V1_RESULT.md:93-97` (“no ... account UI strings”), `distribution/app-store/submission-checklist.md:13`, and live privacy text saying v1 has no public-username feature (`web/public/privacy/index.html:25-26`). No account endpoint or Sign in with Apple entitlement was found, so this is evidence/copy hardening rather than a demonstrated reachable account flow. | Compile the receipt username state, payload input, toggle, and account-linked copy out under `GUEST_ONLY_V1`; give Release a guest-only initializer/API so a future call site cannot inject a username. Add a Release-binary regression check for `public username`, `Show @`, account route strings, the dev Worker host, and `AuthenticationServices.framework`. Rebuild and re-sign; update the signed-IPA report from the actual replacement IPA. |
| **Medium** | **Signed-status expiry is not monotonic across reboot, so local clock rollback can extend a cached authorization.** | On the same boot, `trustedTimeFloor` advances by system uptime. After a boot change, it falls back to the prior verification wall clock (`ios/AIC/PackStatus/PackStatusClient.swift:278-285`). The verifier uses `max(now, trustedTimeFloor)` (`ios/AICCore/PackStatus.swift:282-287`). Rebooting and holding wall time near the last verification can therefore prevent effective time from reaching `expiresAtUnix`. Tests cover same-boot trusted-floor expiry but not reboot plus clock rollback. The separate pack cutoff also uses `Date()` (`ios/AICCore/ChicagoPack.swift:689-705`). | Define the threat/availability policy explicitly. For strict fail-closed behavior, require a successful status refresh after a detected boot change before authorizing scans, or use a trusted-time design that cannot remain frozen across boots. Add deterministic tests for reboot, backward wall-clock movement, forward movement, offline behavior, and recovery. If deliberate user clock tampering is outside the security objective, document the limitation and stop claiming rollback-resistant expiry without qualification. |

## Passed areas

### Release guest behavior and signed package

- Release build settings resolve `GUEST_ONLY_V1`, production bundle identifier `com.binhnguyenhealth.aic`, and only the fixed HTTPS status URL; no account API or account-deletion URL is present.
- Release startup sets `.guest` directly, and sign-in/authentication screens and account settings are conditionally excluded. The signed IPA has no Sign in with Apple entitlement and does not link `AuthenticationServices.framework`.
- The signed IPA verifies with `codesign --verify --deep --strict`; version/build are `1.0.0`/`1`; `get-task-allow` is false; the embedded privacy manifest declares no collected-data types and only the UserDefaults required-reason API.
- The IPA was built minutes before commit `315e07b` and its pack/status resources match the committed resources exactly. Exact source-to-binary provenance is still listed as UNVERIFIED below because no reproducible build attestation binds the IPA hash to the Git tree.

### Pack integrity, freshness, and status logic

- Canonical and bundled SQLite packs have SHA-256 `1a18629fa3429eefec10d0d025c80102ce7c48a63457e601c1c404001686ca32`.
- `pipeline/verify_pack.py` reports schema v3, 23,630 fixed-domain cells, 77 community areas, 2,003 eligible references, three parity fixtures, and no exact/residual total. All four published checksums pass.
- The signed live/bundled status is threshold-valid, sequence 2, and lists that exact pack hash as active. The request is a fixed HTTPS GET with no query or body. Rollback, equivocation, signature threshold, terminal withdrawal, bounded lifetime, and local freshness boundaries have focused core tests.
- The local scan engine checks signed status before reading freshness or scanning, and the SQLite engine independently refuses scans at the `2026-08-07T00:00:00Z` cutoff.

### UI copy, screenshots, and public pages

- The three 1320×2868 screenshots were visually inspected. They are readable, not visibly clipped in the primary content, contain no account/sign-in UI, and consistently label the product historical/not live. Screenshot 03 says the receipt never includes a username.
- Metadata, review notes, screenshots, README, privacy, support, terms, account-deletion, and methodology copy consistently describe guest-only v1, on-device coordinate processing, historical limitations, no background location, and the fixed global status request.
- Privacy, support, terms, methodology, account-deletion, and status URLs returned HTTPS 200. Each live HTML page was byte-identical to its checked-in `web/public` file. The live status object was byte-identical to both public checked-in copies and the bundled bootstrap.
- The City notice appears in the App Store description and live terms page. Current City dataset metadata still identifies the crime dataset as official, attributed to CPD, preliminary/revisable, and licensed under “See Terms of Use.” Qualified legal review remains required.

## Exact App Store form answers supported by this candidate

These are engineering-supported answers for the fixed, rebuilt guest-only binary. The account holder remains responsible for the attestations and must recheck the processed build.

| Field | Answer |
| --- | --- |
| App Review sign-in required | **No** |
| Demo account | **Not applicable; do not provide credentials** |
| App Privacy collection | **No, we do not collect data from this app**, provided Cloudflare retains no status-request IP/HTTP logs for AIC beyond transient delivery/security processing that Apple treats as collection by the developer or a partner. Confirm the deployed retention configuration first. |
| Tracking / advertising identifier | **No / none** |
| Precise and coarse location collection | **No**; foreground precise location and manual pins are processed only on-device and are not transmitted. |
| Background location | **No** |
| User-generated or publicly hosted content | **No**; a user-created image leaves only through the user-invoked iOS share sheet. |
| Export compliance | The binary uses CryptoKit Ed25519 verification and Apple HTTPS. Keep `ITSAppUsesNonExemptEncryption=NO` only if the account holder confirms the app is exempt/no documentation is required through Apple's current questionnaire; do **not** answer that it contains no encryption. Apple explicitly includes standard algorithms and OS crypto in the export-compliance determination. |
| Content rights | **Contains/uses third-party City of Chicago data; attest necessary rights only after qualified review of current City/CPD terms and intended storefronts.** |
| Age-rating capabilities | No unrestricted web access, UGC, social media, messaging/chat, advertising, gambling, contests, or loot boxes. External policy links open fixed pages; verify App Store Connect's current interpretation. |
| Age-rating mature/violence content | The app names real-world crime categories and displays aggregate counts but depicts no violence, weapons, injury, or gore. Under Apple's current definitions, consider **infrequent mature or suggestive themes** for real-world crimes; answer realistic violence and graphic violence **None** because there is no depiction. Let Apple calculate the rating. |
| Made for Kids | **No** |
| Privacy Policy URL | `https://aic-beta-info.binhnguyenhealth.workers.dev/privacy/` |
| Support URL | `https://aic-beta-info.binhnguyenhealth.workers.dev/support/` |
| Reviewer notes | Use `distribution/app-store/review-notes.md` after updating status-expiry evidence and the replacement IPA hash. |

Official references checked on 2026-07-12/13:

- Apple, [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- Apple, [Overview of export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
- Apple, [Age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions)
- Apple, [App Store review details](https://developer.apple.com/documentation/appstoreconnectapi/app-store-review-details)
- City of Chicago, [Crimes — 2001 to Present metadata](https://data.cityofchicago.org/api/views/ijzp-q8t2)

## Commands and checks performed

Targeted inspection and provenance:

```sh
git status --short --branch
git rev-parse --verify 315e07b^{commit}
git rev-parse --verify origin/main^{commit}
git log --oneline origin/main..315e07b
git diff --stat --no-renames origin/main..315e07b
git diff --name-status --no-renames origin/main..315e07b
git diff --check origin/main..315e07b
rg ... <release code, metadata, policies, evidence, and tests>
```

Pack and signed-status validation:

```sh
swift run --package-path ios AICPackStatusValidation \
  ios/AIC/Resources/chicago_beta.sqlite \
  ios/AIC/Resources/pack_status_bootstrap.json \
  /tmp/aic-live-status.json
# AIC_PACK_STATUS_VALIDATION_OK; sequence=2; expires_at=2026-07-20T02:40:16Z

python3 pipeline/verify_pack.py data/chicago_beta.sqlite data/chicago_beta.manifest.json
(cd data && shasum -a 256 -c chicago_beta.checksums.sha256)
shasum -a 256 data/chicago_beta.sqlite ios/AIC/Resources/chicago_beta.sqlite
```

Configuration and signed IPA inspection:

```sh
plutil -lint ios/AIC/Config/Info.plist ios/AIC/Config/AIC.entitlements \
  ios/AIC/Resources/PrivacyInfo.xcprivacy
xcodebuild -project ios/AIC.xcodeproj -scheme AIC -configuration Release \
  -showBuildSettings
shasum -a 256 build/export-app-store/AIC.ipa
ditto -x -k build/export-app-store/AIC.ipa /tmp/aic-audit-ipa
codesign --verify --deep --strict /tmp/aic-audit-ipa/Payload/AIC.app
codesign -d --entitlements :- /tmp/aic-audit-ipa/Payload/AIC.app
plutil -p /tmp/aic-audit-ipa/Payload/AIC.app/Info.plist
plutil -p /tmp/aic-audit-ipa/Payload/AIC.app/PrivacyInfo.xcprivacy
otool -L /tmp/aic-audit-ipa/Payload/AIC.app/AIC
strings /tmp/aic-audit-ipa/Payload/AIC.app/AIC | \
  rg -i 'aic-account-dev|Sign in with Apple|Delete account|public username|/v1/auth|/v1/usernames|/v1/account'
```

Live readback (safe unauthenticated GET only):

```sh
curl -sS --max-time 15 <privacy/support/terms/methodology/account-deletion/status URLs>
cmp /tmp/aic-live-<page>.html web/public/<page>/index.html
shasum -a 256 /tmp/aic-live-status.json web/public/pack-status/v1/status.json
```

The three App Store screenshots were inspected directly. The full Swift/Xcode/pipeline suites were not repeated because the candidate already records recent passing runs and targeted validation was enough to confirm the findings. No simulator was booted or touched.

## Remaining UNVERIFIED items

- **UNVERIFIED:** exact reproducible source-to-binary binding of IPA SHA-256 `0b51e2...2a23` to commit `315e07b`; the artifact predates the commit by minutes, although its committed pack/status resources and reported settings match.
- **UNVERIFIED:** final replacement IPA after the username residue and status-operability findings are fixed.
- **UNVERIFIED:** App Store server-side processing, validation warnings, and final entitlements/privacy readback from the processed build.
- **UNVERIFIED:** physical-device/TestFlight clean install, location allow/deny behavior, manual pin, share/cancel, offline restart, status renewal/withdrawal/omission, and all three freshness UI states.
- **UNVERIFIED:** an end-to-end status renewal or withdrawal drill, independent expiry alert, two-of-three custodian availability, and recovery after expiry.
- **UNVERIFIED:** disclosure/statistical claims against the retained private source snapshots by an independent reviewer.
- **UNVERIFIED:** qualified legal/privacy review of City/CPD terms, content rights, privacy language, correction process, storefront scope, and DSA/operator obligations.
- **UNVERIFIED:** App Store Connect record, agreements, tax/banking status, review contact, privacy answers, age rating, content-rights answer, export-compliance determination, pricing/availability, and final screenshots.

## Minimum GO gate

1. Remove the dormant username receipt path from Release and produce a new signed IPA with a truthful binary-inspection report.
2. Close and evidence the status-service operating loop: owner, backup, independent alert, recurring higher-sequence renewal, deployed readback, and a controlled withdrawal/recovery drill.
3. Resolve or explicitly accept the reboot/time-rollback limitation with tests and accurate documentation.
4. Complete the independent statistical and qualified legal/privacy reviews.
5. Process the exact replacement build through App Store Connect and pass a physical-device TestFlight smoke test, including freshness/status fail-closed states.
6. Reconcile every checklist item and form answer against the processed build immediately before an explicitly authorized submission.

Until all six are complete: **NO-GO**.
