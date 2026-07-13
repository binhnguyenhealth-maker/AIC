# App Store forms final QA

**Audited commit:** `315e07ba2e7b6a09cd1eda760c7b42238e9f975a` (`main`)

**Audit date:** 2026-07-12 (America/New_York)

**Candidate:** `build/export-app-store/AIC.ipa`

**Candidate SHA-256:** `0b51e253572543a8f7916a9517f280b067150f55a023de0c25b99b7794502a23`

## Verdict

**NO-GO for Add for Review / Submit for Review.**

The guest-only metadata, screenshots, public URLs, version/build values, signing,
entitlements, privacy manifest, and age-rating draft are internally consistent.
The IPA is a valid App Store-signed iPhone package for
`com.binhnguyenhealth.aic`, version `1.0.0` build `1`.

Submission is not yet safe because the pack-status host's request-IP retention
has not been established, so the proposed **No data collected** response cannot
yet be attested; the signed executable still contains dormant account client
implementation; the IPA predates the audited commit and has no evidence tying
the archive to that exact Git tree; and the processed-build/physical-device
path plus required private and account-holder form values remain unverified.

This is engineering and metadata QA, not legal or export-control advice.

## Blockers

| Severity | Blocker | Direct evidence | Required closure |
| --- | --- | --- | --- |
| **High** | App Privacy cannot yet be truthfully finalized as **No data collected** | The app performs a fixed HTTPS pack-status request (`ios/AIC/PackStatus/PackStatusClient.swift`), and the privacy policy says Cloudflare receives the request IP and HTTP/TLS metadata. `web/wrangler.jsonc` identifies the asset Worker but contains no retention/logging evidence. Apple defines collection by retention beyond real-time request servicing and says a non-retained IP need not be disclosed; retained data must be considered. | Establish and retain evidence for the production host's actual request-log/security-log retention and access. If request IP/metadata is not retained beyond real-time servicing, use the no-collection answer below. If it is retained, use the conservative alternate disclosure below and update `distribution/app-store/privacy-labels.md` and the public privacy policy before submission. |
| **High** | The signed binary is not proven to be built from the exact audited commit | The IPA modification time is `2026-07-12T23:00:01-0400`; commit `315e07b` was created at `2026-07-12T23:08:19-04:00`. The archive/IPA contains no recorded source commit. Signature and resource readback prove package integrity, not source-tree provenance. | From a clean intended release commit, archive/export again, record `git rev-parse HEAD` immediately before the build, and bind that SHA to the new IPA SHA-256 in the validation report. Do this only with explicit authorization for signing/provisioning. |
| **Medium** | Dormant account implementation remains in the guest-only executable | `GUEST_ONLY_V1` removes the account UI and the signed app has no Sign in with Apple entitlement or account endpoint in `Info.plist`. However, `strings Payload/AIC.app/AIC` still contains `AccountAPI`, `AccountAPIProtocol`, username/account copy, and account-related symbols. Apple Guideline 2.3.1(a) warns against hidden, dormant, or undocumented functionality. | Exclude the account API, credential store, Apple nonce, and authentication screens from the Release target (or wrap the complete implementations in `#if !GUEST_ONLY_V1`), then rebuild and confirm the account symbols/endpoints are absent. Preserve the receipt's truthful guest-only “no username” copy. |
| **High** | Final processed build and physical-device behavior are unverified | `distribution/app-store/submission-checklist.md` leaves upload, App Store processing, internal TestFlight install, physical-device smoke testing, and final status-state tests unchecked. This audit did not access App Store Connect or any simulator/device. | Upload only after the new candidate passes this report, wait for processing, install that exact build from TestFlight on a physical iPhone, and exercise permission allow/deny, manual pin, receipt/share cancel, support/privacy links, foreground refresh, and active/paused/expired pack states. |
| **High** | Required App Store Connect/account-holder values and legal attestations are absent | The repository intentionally does not contain the private review contact. It cannot prove the App Store record, agreements, DSA status, pricing/availability, exact copyright owner, Content Rights attestation, or form publication state. | The account holder must supply/confirm the values listed under **Missing account values** and personally make the legal, privacy, export, and rights attestations. Do not put private review-contact data in Git. |

## Paste-ready App Privacy answers

Apple defines “collect” as transmitting data off device in a way that lets the
developer or a partner access it longer than needed to service the request in
real time. Apple also explicitly says on-device-only location is not collected
and a non-retained IP used only to service a request need not be disclosed. See
[App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
and [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/).

### Primary answer — use only after proving no request-IP retention

| App Store Connect prompt | Answer |
| --- | --- |
| Do you or your third-party partners collect data from this app? | **No, we do not collect data from this app** |
| Tracking | **No** |
| Data used to track the user | **None** |
| Privacy Policy URL | `https://aic-beta-info.binhnguyenhealth.workers.dev/privacy/` |
| User Privacy Choices URL | **Leave blank** (optional; v1 has no account or developer-held user data) |

Rationale: current and manual-pin locations are processed only on device; scan
coordinates, derived cells, scan history, receipt images, and share destinations
are not sent to AIC. The only app-originated service request is a rate-limited
GET for a fixed global status object with no query or request body.

### Conservative alternate — use if the host retains IP/request metadata

| App Store Connect prompt | Answer |
| --- | --- |
| Do you or your third-party partners collect data from this app? | **Yes, we collect data from this app** |
| Data type | **Other Data Types** |
| Purpose | **App Functionality** (service delivery, security, uptime, and pack withdrawal) |
| Linked to the user | **Yes** (conservative treatment of retained IP/personal data) |
| Used for tracking | **No** |
| Tracking | **No** |

Do not select precise or coarse location merely because an IP exists. The app
does not transmit the Core Location value or a scan-derived location. Reconcile
the alternate answer with the provider's exact retention/use before publishing.

The signed `PrivacyInfo.xcprivacy` is consistent with the primary answer: it
declares no collected data, no tracking, no tracking domains, and only the
`CA92.1` UserDefaults required-reason API.

## Paste-ready age rating answers

Apple's current questionnaire asks for presence or frequency by category and
calculates global and region-specific ratings. Apple's definition expressly
lists **real-world crimes** under Mature or Suggestive Themes. See
[Age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions)
and [Set an app age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating).

| Questionnaire item | Answer |
| --- | --- |
| Parental Controls | **No** |
| Age Assurance | **No** |
| Unrestricted Web Access | **No** |
| User-Generated Content | **No** |
| Social Media | **No** |
| Messaging and Chat | **No** |
| Advertising | **No** |
| Profanity or Crude Humor | **None** |
| Horror/Fear Themes | **None** |
| Alcohol, Tobacco, or Drug Use or References | **None** |
| Medical or Treatment Information | **None** |
| Health or Wellness Topics | **None** |
| Mature or Suggestive Themes | **Infrequent** — historical real-world crime categories |
| Sexual Content or Nudity | **None** |
| Graphic Sexual Content and Nudity | **None** |
| Cartoon or Fantasy Violence | **None** |
| Realistic Violence | **None** — labels/counts only; no depiction of physical conflict or injury |
| Prolonged Graphic or Sadistic Realistic Violence | **None** |
| Guns or Other Weapons | **None** |
| Gambling | **No / None** |
| Simulated Gambling | **None** |
| Contests | **None** |
| Loot Boxes | **No** |
| Age Categories and Override | **Not Applicable** |
| Made for Kids | **No** |
| Override to Higher Age Rating | **No** |
| Age Suitability URL | **Leave blank** |

Expected Apple global result for iOS 26-era ratings: **9+**, because of
infrequent Mature or Suggestive Themes. Apple, not this report, calculates the
authoritative global and regional ratings; inspect the result before saving.
Apple's current documentation also retains the legacy scale for devices running
pre-iOS 26 operating systems, where this answer may display as **12+**. That is
not a conflict and should not be manually overridden.

## Paste-ready encryption / export compliance answers

The signed app's final `Info.plist` contains
`ITSAppUsesNonExemptEncryption = false`. Its only network use is HTTPS through
Apple's operating-system networking stack, and `otool -L` found Apple system
frameworks plus the app's own `AICCore.framework`, with no third-party crypto
framework. Apple says this key should be `NO` when the app and linked libraries
use no encryption or only exempt encryption. See
[ITSAppUsesNonExemptEncryption](https://developer.apple.com/documentation/BundleResources/Information-Property-List/ITSAppUsesNonExemptEncryption)
and [Overview of export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance).

Use these answers if App Store Connect still asks:

| Prompt/concept | Answer |
| --- | --- |
| Does the app use non-exempt encryption? | **No** |
| Does the app implement proprietary or non-standard cryptographic algorithms? | **No** |
| Does the app implement standard cryptographic algorithms itself or through a bundled third-party library? | **No** |
| Does the app rely only on encryption available within Apple's operating system (HTTPS/TLS)? | **Yes** |
| Is export-compliance documentation required for this build? | **No**, based on the inspected binary and `ITSAppUsesNonExemptEncryption = NO` |

Stop and reassess if any non-Apple cryptographic implementation or SDK is added.

## Paste-ready Content Rights answer

Apple requires apps that contain, show, or access third-party content to have
the necessary rights or other legal permission in every offered country or
region. See [App information — Content Rights](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)
and App Review Guideline 5.2.

The app contains derived aggregates from City of Chicago datasets
`ijzp-q8t2`, `c7ck-438e`, and `igwz-8jzy`. The repository's dated evidence
record (`docs/research/CHICAGO_TERMS_EVIDENCE_2026-07-12.md`) documents the
official terms and dataset metadata. The prescribed City notice appears in the
App Store description and the live Terms page.

**Form answer, only after the account holder accepts the legal attestation:**

> **Yes — this app contains, shows, or accesses third-party content, and I have
> the necessary rights or permission to use it.**

This is not a “no third-party content” app. The account holder should limit
initial availability to jurisdictions covered by the rights assessment and
obtain qualified advice if the City terms or intended distribution remain
ambiguous.

## Paste-ready App Review notes

```text
AIC is a Chicago-only historical-data app. It has no account, sign-in, purchase, advertising, user-generated-content, or reviewer-credential flow. All functionality is available immediately after launch.

Review path:
1. Launch the app; it opens the guest Home screen.
2. Tap “Scan My Area” to request foreground location, or deny permission and tap “Choose another spot” to use the offline Chicago picker.
3. Review the Cooked Score and the adjacent “DATA THROUGH 2026-06-30 · NOT LIVE” disclosure.
4. Tap “Generate Cooked Report” to open the Cooked Receipt. The receipt contains no exact coordinates, address, route, or exact timestamp; the reviewer may hide the approximate neighborhood.
5. Tap “Share image” to inspect the native iOS share sheet, then cancel. AIC does not upload the receipt.

Normal current-location scans and manual pins are processed on device against the bundled SQLite data pack. AIC does not transmit scan coordinates, addresses, routes, scan-derived cells, or scan history and does not request background location.

At launch and foreground, no more than once per 15 minutes, AIC may fetch one fixed global signed pack-status JSON file so a materially flawed pack can be withdrawn. The request contains no city, coordinate, scan, account, device identifier, installed-pack identifier, query, or body. Pressing Scan does not trigger this request.

Cooked Score is a historical data index, not a live safety assessment or personal-risk prediction. Do not use it for emergency, navigation, or route decisions.
```

App Review contact name, monitored email, and telephone belong in the private
App Review Information fields, not in these notes or this repository.

## Metadata, URLs, and assets

| Field | Paste-ready value / result |
| --- | --- |
| App name | `AIC: Am I Cooked?` — 17 characters, limit 30 |
| Subtitle | `Chicago history, locally` — 24 characters, limit 30 |
| Promotional text | `Scan a Chicago location against historical reported-incident concentration—processed privately on your iPhone.` — 110 characters, limit 170 |
| Description | Use `distribution/app-store/metadata/en-US/description.txt` — 2,568 characters excluding final newline, limit 4,000 |
| Keywords | `Chicago,crime,data,history,neighborhood,incident,local,privacy,community,statistics` — 83 bytes excluding final newline, limit 100 bytes |
| Support URL | `https://aic-beta-info.binhnguyenhealth.workers.dev/support/` — HTTP 200, contains monitored email and issue path |
| Privacy Policy URL | `https://aic-beta-info.binhnguyenhealth.workers.dev/privacy/` — HTTP 200 |
| Marketing URL | `https://aic-beta-info.binhnguyenhealth.workers.dev/` — HTTP 200 |
| Version | `1.0.0` |
| Build | `1` |
| Bundle ID | `com.binhnguyenhealth.aic` |
| Platform / device family | iOS / iPhone only |
| Minimum OS | iOS 17.0 |
| Sign-in required | **No** |
| App icon | 1024×1024 RGB PNG, no alpha |
| Screenshots | Three visually inspected 1320×2868 portrait PNGs; valid current 6.9-inch size; accurate guest-only Home, Result, and Receipt states |
| App preview | Leave blank; optional |
| What's New | Not available for first version |

Apple currently allows one to ten `.jpeg`, `.jpg`, or `.png` screenshots and
accepts 1320×2868 for a 6.9-inch portrait slot. See
[Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
and [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/).

No additional iPad screenshots are required because the signed app declares
device family `1` (iPhone only). Actual App Store Connect upload/processing of
the files remains unverified.

## Missing account values

These cannot be truthfully inferred from source control:

| Field | Recommended draft | Required owner action |
| --- | --- | --- |
| SKU | `AIC-IOS-1` | Approve before record creation; SKU is consequential and not user-facing |
| Primary language | English (U.S.) | Confirm |
| Primary category | Reference | Confirm |
| Secondary category | Lifestyle or blank | Confirm; optional |
| Copyright | `2026 Binh Nguyen` | Confirm exact legal rights-owner name; Apple adds the copyright symbol |
| Price | Free | Confirm |
| Initial availability | United States only | Confirm rights and business choice |
| Release method | Manual release | Confirm |
| App Review contact | **Missing/private** | Enter monitored individual name, email, and phone directly in App Store Connect |
| App Store Connect app record / Apple ID | **UNVERIFIED** | Create/select without changing the final Bundle ID |
| Agreements, tax, and banking | **UNVERIFIED** | Account holder confirms no distribution blocker |
| DSA trader status | **UNVERIFIED** | Account holder makes the legally accurate declaration |
| Regulated medical device | **No** | Confirm; the app makes no medical-device claim |
| License agreement | Apple's standard EULA | Confirm that no custom EULA is intended |
| Accessibility Nutrition Labels | **UNVERIFIED** | Complete only from tested final binary behavior; do not overclaim |

## Checks and commands performed

The following read-only or local verification was performed against commit
`315e07b`; no account, profile, simulator, upload, or deployment action occurred:

```sh
git status --short --branch
git rev-parse HEAD
git diff-tree --no-commit-id --name-status -r 315e07b
git show --no-patch --format=... 315e07b

shasum -a 256 build/export-app-store/AIC.ipa
codesign --verify --deep --strict --verbose=2 build/ipa-inspect/Payload/AIC.app
codesign -d --entitlements :- build/ipa-inspect/Payload/AIC.app
plutil -p build/ipa-inspect/Payload/AIC.app/Info.plist
plutil -p build/ipa-inspect/Payload/AIC.app/PrivacyInfo.xcprivacy
otool -L build/ipa-inspect/Payload/AIC.app/AIC
strings build/ipa-inspect/Payload/AIC.app/AIC | rg 'https?://|Account|Sign in|username|workers.dev|telemetry|analytics'

file distribution/app-store/screenshots/en-US/*.png
shasum -a 256 distribution/app-store/screenshots/en-US/*.png
sips -g pixelWidth -g pixelHeight -g format -g hasAlpha -g space <asset>
# All three screenshots were also visually inspected at original resolution.

curl -L -sS --max-time 15 <public URL>
# Privacy, support, marketing, terms, methodology, and pack-status URLs returned HTTP 200.

(cd ios && swift test)
# 40 tests passed, 0 failures.
```

Official Apple primary documentation was checked on 2026-07-12 for App Privacy,
age ratings, export compliance, Content Rights, metadata limits, and screenshot
sizes.

## Remaining UNVERIFIED items

- Cloudflare production request-IP and HTTP/TLS metadata retention, access, and
  purpose; this controls the final App Privacy branch.
- Exact source-tree provenance of the signed IPA; its package predates the
  audited commit by about eight minutes.
- App Store Connect record existence, role/access, agreements, DSA, tax,
  banking, pricing, availability, copyright, category, and form state.
- App Store upload acceptance, processing warnings, privacy-manifest analysis,
  and selection of build `1`.
- TestFlight installation and end-to-end smoke testing on a physical iPhone.
- The final device behavior of active, update-due-soon, remotely paused,
  signature-failure, cached-status-expiry, and local pack-expiry states.
- Qualified legal review of City terms, redistribution, claims, corrections,
  privacy policy, and the account holder's Content Rights attestation.
- Qualified export-control review; the engineering evidence supports
  `ITSAppUsesNonExemptEncryption = NO`, but this report is not legal advice.
- Final App Store-generated global/regional age ratings after the questionnaire
  is entered.
- App Store Connect screenshot upload/processing and storefront rendering.

Do not submit until every **High** blocker is closed and the final privacy branch
is reconciled across the binary, host behavior, privacy policy, privacy manifest,
and App Store Connect.
