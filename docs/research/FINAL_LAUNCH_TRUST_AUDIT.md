# Final Launch / Trust Audit

**Audited revision:** `0446c4b739cb23a247f537cdcee09538f523a433`

**Audit date:** 2026-07-12 (America/New_York)

**Scope:** Shipped Chicago-only iOS release candidate, bundled data pack, account Worker, public information site, App Store metadata, screenshots, claims, privacy/security controls, source rights, and correction/withdrawal readiness. Expansion research in another worktree was not reviewed as shipped product.
**Result:** **FAIL — NO-GO for App Store submission**

The local scan product, guest path, disclosures, screenshots, pack integrity, and automated core/Worker tests are strong. Submission is still unsafe because the in-app account-deletion path predictably breaks after access-token expiry; current City data terms are not satisfied on any inspected download/access surface; the release's central source-to-pack disclosure audit cannot be reproduced; production Apple/account lifecycle and signing gates are unproved; and there is no tested emergency correction/withdrawal path before the bundled cutoff.

This is an engineering and launch-readiness audit, not legal advice. Findings marked **legal review required** need qualified counsel before launch.

## Mandatory before submit

### 1. High — Account deletion fails after the 15-minute access token expires; logout can contradict its revocation claim

**Status:** **FAIL / product blocker**

The Worker issues access JWTs for 15 minutes (`services/account-worker/src/sessions.ts:9-10`, `:26-40`) and rejects expired JWTs in `authenticate` (`services/account-worker/src/sessions.ts:79-108`). Apple reauthentication, logout, and account deletion all authenticate that JWT first (`services/account-worker/src/index.ts:187-189`, `:313-323`, `:326-335`).

The client refreshes only while restoring a session at launch (`ios/AIC/App/AppModel.swift:114-136`). It does not refresh before reauthentication/deletion (`ios/AIC/App/AppModel.swift:249-270`) or logout (`ios/AIC/App/AppModel.swift:226-239`). Therefore, after ordinary foreground use exceeding about 15 minutes:

- the fresh Sign in with Apple deletion flow reaches the Worker with an expired AIC access token and receives `401` before a deletion proof can be issued;
- deletion cannot complete despite the in-app control; and
- logout discards the local refresh credential after swallowing the failed server request, while the server session was not explicitly revoked.

The Settings footer says logout revokes the active session (`ios/AIC/Features/Settings/SettingsScreen.swift:78-85`), which is not always true. Existing app tests exercise only a fresh 15-minute fixture and do not cover expiry (`ios/Tests/AICAppTests/AccountDeletionTests.swift:68-93`, `:96-105`).

Apple requires apps that support account creation to let users initiate deletion in-app and expects the flow to be straightforward and functional: [App Review Guidelines 5.1.1(v)](https://developer.apple.com/app-store/review/guidelines/) and [Offering account deletion in your app](https://developer.apple.com/support/offering-account-deletion-in-your-app/).

**Required closure:** refresh before every authenticated sensitive operation, or perform one safe refresh-and-retry on authentication expiry; do not silently claim remote revocation on failure; add expired-token deletion/logout tests at client and Worker boundaries; then validate the final production flow end to end.

### 2. High — Required City of Chicago derivative-application disclaimer is absent

**Status:** **FAIL / legal-review issue**

The official [City of Chicago Data Terms of Use](https://www.chicago.gov/city/en/narr/foia/data_disclaimer.html) state that a secondary or derivative application using City-supplied data shall include the City's prescribed disclaimer at the site where the application can be accessed or downloaded. The three current dataset metadata records also identify their license as `See Terms of Use` (City dataset IDs `ijzp-q8t2`, `c7ck-438e`, and `igwz-8jzy`).

A repository-wide exact-text search found no instance of the prescribed notice. It is absent from the App Store description (`distribution/app-store/metadata/en-US/description.txt:1-21`), public terms (`web/public/terms/index.html:12-34`), and source-rights page (`DATA_SOURCES.md:44-49`). The deployed terms page was also checked and does not contain it.

The repository correctly says its MIT license applies to software and does not expand third-party data rights (`DATA_SOURCES.md:44-49`), but that does not satisfy the separate display requirement.

**Required closure:** obtain qualified review of the current City and any agency-specific terms; place the exact required notice on the legally appropriate App Store/download/access surface(s); deploy and read it back; retain a dated terms-evidence record. Counsel should also confirm that distributing the derived SQLite pack is adequately covered by the documented software/data license separation. Do not represent this audit as a legal clearance.

### 3. High — The existing release's source-to-pack disclosure proof cannot be reproduced

**Status:** **FAIL / trust-evidence blocker**

The documented disclosure verifier rebuilds the released bands from the exact incident and boundary snapshots (`pipeline/README.md:22-36`; `pipeline/audit_disclosure.py:25-58`). Those release inputs are deliberately ignored (`pipeline/.gitignore:1`) and are absent from this checkout. The manifest preserves their hashes (`data/chicago_beta.manifest.json:264-290`) but not the inputs.

The required command failed with:

```text
FileNotFoundError: pipeline/.cache/incidents_iucr_v3_2025-07-01_2026-07-01.jsonl.gz
```

This prevents independent confirmation of the exact shipped pack's source histogram, outside-boundary filtering, low-count handling, relocation trials, and measured utility claims. Those claims are asserted in `docs/methodology/BETA_SCORE.md:180-225`.

The checksum and schema verifier passing is useful but not equivalent: it proves the checked-in artifacts are internally consistent, not that the unavailable source snapshots produce them.

**Required closure:** recover the exact hash-matching source snapshots in a controlled private audit location and rerun `pipeline/audit_disclosure.py`, preserving the result; or rebuild a new release candidate from newly retained inputs and rerun the full disclosure/utility audit. Refreshing mutable City sources cannot validate this existing pack.

### 4. High — Final production account, signing, device, and App Store review path is unvalidated

**Status:** **FAIL / App Review completeness blocker**

Both build configurations resolve the account API to the dev-named endpoint (`ios/project.yml:72-85`; generated settings at `ios/AIC.xcodeproj/project.pbxproj:777-803`). The checked-in Worker configuration is also dev-named and contains placeholder Apple team/key identifiers (`services/account-worker/wrangler.jsonc:3-23`). A public `GET /health` returned `200`, but that does not validate Apple exchange, token refresh, logout, deletion, secret configuration, bundle audience, or entitlement behavior.

The repository explicitly leaves production Sign in with Apple, refresh, logout, and deletion validation open (`distribution/app-store/submission-checklist.md:14`). The Apple Developer team, final App ID/Sign in with Apple capability, App Store Connect record, signing/profile, physical-device Release archive, TestFlight installation, age rating, export compliance, content-rights, and App Privacy forms are also open (`distribution/app-store/submission-checklist.md:23-37`). `ios/project.yml` has no `DEVELOPMENT_TEAM` value (`ios/project.yml:15-18`).

This is especially material because the third screenshot advertises a public username and review notes direct reviewers to optional Sign in with Apple and deletion (`distribution/app-store/screenshots/en-US/03-cooked-receipt-iphone-17-pro-max.png`; `distribution/app-store/review-notes.md:23-31`). Apple requires submitted apps, metadata, URLs, and login backends to be complete and functional: [App Review Guidelines 2.1 and 2.3](https://developer.apple.com/app-store/review/guidelines/).

**Required closure:** after fixing finding 1, configure and read back the final Release archive's bundle ID, entitlement, API URL, and privacy manifest; validate production Apple exchange, refresh across access-token expiry, logout revocation, deletion, and guest fallback on a physical device/TestFlight build; then complete the App Store Connect manual gates. The dev hostname is not itself proof of failure, but the absence of final production evidence is a submission blocker.

### 5. High — No tested emergency pack correction or withdrawal path exists before the local cutoff

**Status:** **FAIL / operational trust blocker**

The app validates only bundled metadata and device time (`ios/AICCore/ChicagoPack.swift:572-609`, `:689-710`). The scan path uses the local bundled engine (`ios/AIC/Features/Home/HomeScreen.swift:18`, `:225-252`) and has no inspected correction/revocation channel. If the shipped crime-adjacent pack or methodology is materially wrong, the app will continue scoring until an App Store update reaches the device or the local cutoff blocks it.

The manifest sets `source_through_date` to `2026-06-30` and `fresh_until_date` to `2026-08-07` (`data/chicago_beta.manifest.json:207-213`), leaving less than four weeks at audit time. The repository itself leaves emergency correction/withdrawal, final cutoff-state validation, and refresh ownership open (`distribution/app-store/submission-checklist.md:39-46`).

**Required closure:** establish and exercise a correction/withdrawal runbook with named owner, monitored alert, decision thresholds, App Store stop-distribution/removal steps, corrected-build path, user communication, and evidence capture. If operational withdrawal/update latency is not acceptable, add a narrowly scoped, authenticated, fail-safe pack revocation mechanism and test both availability and abuse resistance. Refresh the pack before submission if review/release timing cannot comfortably precede `2026-08-07T00:00:00Z`.

### 6. High — Support URL does not provide Apple-required direct contact information

**Status:** **FAIL / likely metadata rejection**

The App Store Support URL points to the deployed support page (`distribution/app-store/metadata/en-US/support_url.txt:1`). That page offers only a public GitHub issue tracker and warns users not to post location, account, authentication, or personal data (`web/public/support/index.html:15-16`). The privacy and deletion pages send users to the same public channel (`web/public/privacy/index.html:38-39`; `web/public/account-deletion/index.html:32-33`). This is unsuitable for sensitive deletion failures and is not actual direct contact information.

Apple's current [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/) requires the Support URL to lead to actual contact information, and [App Review Guideline 1.5](https://developer.apple.com/app-store/review/guidelines/) requires an easy way to contact the developer in the app and at the Support URL.

**Required closure:** add a monitored private contact route and accurate current developer contact information to the support surface, make it reachable from the app, deploy it, and read it back. Ask counsel what operator/controller identity and address disclosures are required for intended storefronts.

### 7. Medium — Published IUCR launch hash is wrong

**Status:** **FAIL / documentation integrity blocker**

`docs/methodology/IUCR_MAPPING.md:3-9` identifies the machine-readable mapping but claims its schema-v3 launch SHA-256 is:

```text
3b7b0b6f8ffca3bdb33e09dae149b099b748e2252a22755330834bea32018072
```

The actual file hash is:

```text
a340d5433f43489720609793b332466a8a16b2587052aafb2f34843360ae0f02
```

The actual value agrees with the release manifest (`data/chicago_beta.manifest.json:101-105`) and shipped SQLite metadata. A launch document that provides a false integrity anchor undermines reproducibility even though the artifact itself is internally consistent.

**Required closure:** correct the methodology reference and verify all published integrity anchors against the release artifacts before submission.

## Passed areas

### Guest flow and privacy claims

- A clean install with no stored session enters `.guest` (`ios/AIC/App/AppModel.swift:114-136`), and guest state routes to the complete main scan flow (`ios/AIC/App/AICApp.swift:22-34`, `:68-70`).
- Sign in is optional; the manual Chicago picker remains available without location permission (`ios/AIC/Features/Home/HomeScreen.swift:104-133`, `:148-176`).
- Normal scans use the bundled local engine (`ios/AIC/Services/LocalScanEngine.swift:9-37`). Targeted source inspection found no scan-coordinate upload endpoint, and app tests assert that current/manual scan, receipt render, and canceled share make no network request (`ios/Tests/AICAppTests/LocalOperationNetworkPrivacyTests.swift:40-75`).
- On-device-only location is consistent with Apple's current definition of data that is not “collected” for App Privacy purposes: [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/). The declared User ID and Other User Content match the optional account/username behavior (`ios/AIC/Resources/PrivacyInfo.xcprivacy:1-37`; `distribution/app-store/privacy-labels.md:7-22`).

### Claims, metadata, screenshots, and public pages

- User-facing copy consistently says historical, estimated, not live, and not a personal-risk prediction (`distribution/app-store/metadata/en-US/description.txt:13-21`; `distribution/app-store/review-notes.md:3-20`; `web/public/methodology/index.html:12-40`).
- The three App Store screenshots were visually inspected. They are readable, show the real core experience and prominent data-through/not-live disclosures, and show no visible clipping. Each is `1320 x 2868`, an accepted 6.9-inch portrait size in Apple's [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).
- The 1024-square App Store icon is RGB with no alpha. Metadata name, subtitle, keyword, promotional-text, and description lengths are within current Apple limits.
- Marketing, privacy, support, methodology, account-deletion, and terms URLs all returned HTTPS `200`. The deployed HTML was byte-identical to the checked-in `web/public` pages at audit time. The checklist's unchecked deployment-readback line (`distribution/app-store/submission-checklist.md:20`) is stale, but finding 6 requires another support-page deployment.

### Integrity, tests, dependencies, and secrets

The following current non-mutating validations passed:

```text
python3 -m unittest discover -s pipeline/tests -v
  19 tests, 0 failures

python3 pipeline/verify_pack.py data/chicago_beta.sqlite data/chicago_beta.manifest.json
  integrity: ok; schema v3; 23,630 fixed-domain cells; 77 community areas;
  2,003 references; 3 parity fixtures; no exact/residual total

(cd data && shasum -a 256 -c chicago_beta.checksums.sha256)
  all four artifacts OK

(cd services/account-worker && npm test)
  28 tests, 0 failures

(cd ios && swift test)
  31 tests, 0 failures

(cd services/account-worker && npm audit --omit=dev)
  0 vulnerabilities

gitleaks git --redact .
  4 commits / approximately 722 KB scanned; no leaks found
```

The canonical pack and bundled iOS pack have the same SHA-256, `821130a16d616c808c795844623c9a134120719685b4ae59303394bcfe8d01e7`.

No simulator or Apple-account action was used, as required. Consequently, app-hosted iOS tests, a signed Release archive, entitlement readback, physical-device behavior, and TestFlight behavior remain **UNVERIFIED** in this audit and are covered by finding 4.

## Post-launch items allowed only after mandatory closure

These are not substitutes for the blockers above:

1. Keep a dated copy/hash of each applicable City/agency terms page and recheck it for every data refresh.
2. Monitor the production account service, revocation outbox, deletion failures, and support inbox with an owner and escalation threshold.
3. Reconcile stale test-count documentation (`README.md:103-109`) with the current 19 Python and 31 Swift package tests.
4. Revalidate App Privacy answers and screenshot/metadata truth against every submitted binary; Apple requires those answers to stay current ([Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)).
5. Do not publish a second rolling-window schema-v3 pack without the multi-release disclosure review already required by `docs/methodology/BETA_SCORE.md:222-225`.

## Final recommendation

**NO-GO. Do not submit commit `0446c4b` to App Review.**

The minimum credible submit gate is: fix and test token-expiry handling for deletion/logout; satisfy the City notice after legal review; reproduce the exact release disclosure audit; correct the IUCR hash; add private direct support; establish and exercise emergency correction/withdrawal; then prove the final signed production Apple/account lifecycle on physical device/TestFlight and complete the App Store Connect gates. After those close, rerun this audit against the exact archive and its final metadata.
