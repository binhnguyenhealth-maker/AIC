# App Store Connect submission runbook — Am I Cooked?

**Prepared:** 2026-07-12 (America/New_York)
**Repository commit inspected:** `0446c4b` (`origin/main`)
**Scope:** executable release plan and automation inventory only. No portal, signing, archive, upload, deployment, or account mutation was performed.

## Executive decision

Ship **guest-only v1**. The scan and receipt flow is already account-free, while production Sign in with Apple is not release-ready: the App ID/capability is unconfirmed, the Worker contains placeholder Apple values, no production end-to-end sign-in/deletion evidence exists, and the account service URL is still the development Worker. Do not archive the current tree unchanged.

Before the release archive, make and review a separate release patch that:

1. removes Sign in with Apple from `ios/project.yml`, `ios/AIC/Config/AIC.entitlements`, and the generated Xcode project;
2. removes or makes unreachable every account/sign-in/username/deletion UI path in the Release build;
3. makes receipts guest-only and removes username controls/copy;
4. revises App Store description/review notes/privacy answers to guest-only;
5. replaces screenshot 03, which currently displays `@chi_builder` and account visibility controls; and
6. proves the final binary makes no account-service calls and has no Sign in with Apple entitlement.

This is a **hard release gate**, not a suggestion. The alternate path is to finish the entire production Sign in with Apple/App ID/Worker/deletion setup and physical-device validation before submission.

## Release facts and current blockers

| Item | Exact value / observed state | Status |
| --- | --- | --- |
| App Store name | `AIC: Am I Cooked?` | Drafted; availability must be checked in App Store Connect |
| On-device display name | `Am I Cooked?` | Verified |
| Bundle ID | `com.binhnguyenhealth.aic` | Verified in source; not verified as registered in Apple Developer |
| Version | `1.0.0` | Verified |
| Build | `1` | Verified |
| Team ID | `GJ96397VV7` | Confirmed by installed Apple Distribution identity and existing team profiles |
| Signing mode | Automatic | Verified in project |
| Distribution identity | `Apple Distribution: BINH CONG NGUYEN (GJ96397VV7)` | Valid; expires 2027-07-13 00:36:50 UTC |
| AIC provisioning profile | None installed | **Blocker until authorized provisioning** |
| Xcode / iOS SDK | Xcode 26.6, build `17F113`; iPhoneOS SDK 26.5 | Verified; meets the iOS 26 SDK upload minimum effective 2026-04-28 |
| Physical iOS device | None found by `devicectl` | **Hard device/TestFlight gate** |
| App Store Connect API credential | No matching env names; no keys in `~/.private_keys` or `~/.appstoreconnect/private_keys` | **Upload/API automation blocker** |
| App Store Connect record | Unknown; read-only scope forbade account inspection | **Hard user/account gate** |
| Agreements / roles / DSA / tax / banking | Unknown | **Hard user/account gate** |
| Current account backend | `https://aic-account-dev.binhnguyenhealth.workers.dev` (root returns 404) | Not acceptable evidence for production sign-in |
| Public information pages | privacy, support, terms, methodology, deletion, and marketing URLs returned HTTP 200 | Verified 2026-07-12 |
| Data horizon | 2025-07-01 through 2026-06-30 | Verified in manifest |
| Pack update window | fresh through 2026-08-07; expires 2026-08-29 | Release must occur with enough review margin or refresh the pack |

## Hard user-present gates

Stop and obtain the account holder's explicit action/confirmation at each gate:

1. Confirm the latest Apple Developer agreements are accepted and the operator has the required App Store Connect role.
2. Register/select `com.binhnguyenhealth.aic` and create/select the iOS App Store Connect record. These are Apple-account mutations.
3. Approve automatic provisioning. `-allowProvisioningUpdates` can create/update App IDs, profiles, and certificates on Apple's portal.
4. Supply either an App Store Connect API key (Issuer ID, Key ID, `.p8`) or a working Xcode/App Store Connect authenticated session. Never paste the `.p8` or password into logs or source control.
5. Decide the immutable or consequential record fields: SKU, app access, app name, storefront availability, legal copyright, category, price, release method, content-rights attestation, DSA trader status, and age-rating answers.
6. Confirm current City of Chicago dataset rights/terms and retain dated evidence before attesting to Content Rights.
7. Provide monitored App Review contact name, private email, and phone number directly in App Store Connect; do not commit them.
8. Attach a physical iPhone, install the processed TestFlight build, and complete the smoke test. No device is currently attached.
9. Personally inspect the final metadata/privacy/age/export answers and the selected processed build before **Add for Review** and **Submit for Review**.

## 24-hour critical path

This path can produce an uploaded, internally tested candidate within 24 hours only if Apple agreements/roles are already active, provisioning succeeds, processing is timely, and a physical iPhone becomes available. App Review approval is not a 24-hour deliverable.

| Window | Owner | Action | Exit evidence |
| --- | --- | --- | --- |
| Hour 0–2 | Developer | Implement guest-only release patch; revise metadata; replace screenshot 03 | Clean reviewed diff; account paths absent |
| Hour 2–4 | Developer | Run all repository tests and a Release generic-device build without signing | Test logs; generated project unchanged after XcodeGen |
| Hour 2–4, parallel | Account holder | Accept agreements; register bundle ID; create App Store Connect record; choose record fields; create least-privilege API key if used | Record Apple ID, Bundle ID, Key/Issuer IDs (not private key contents) |
| Hour 4–6 | Account holder + developer | Authorize automatic provisioning and create archive | `.xcarchive`; archive verification report |
| Hour 6–8 | Developer | Export and validate IPA; inspect signature, profile, Info.plist, privacy manifest, and guest-only entitlements | Validated `.ipa`; no SIWA entitlement |
| Hour 8–10 | Account holder + developer | Complete metadata/privacy/age/export/content-rights/pricing/availability fields | App Store Connect shows no missing fields |
| Hour 10–12 | Account holder | Authorize one upload | Delivery ID and processed build `1` |
| Hour 12–18 | Device owner | Add to internal TestFlight; install on physical iPhone; execute smoke test | Dated device checklist/screenshots; no account UI/network |
| Hour 18–22 | Developer | Resolve processing warnings; final metadata and binary reconciliation | Final go/no-go checklist |
| Hour 22–24 | Account holder | Select build and manually authorize Add for Review / Submit for Review | Submission receipt/status |

If a fresh pack cannot reasonably clear review before 2026-08-07, refresh and revalidate the pack before archive rather than racing its update window.

## App Store Connect record and exact fields

### New App record

Apple requires the record before the first upload.

| Field | Recommended value | Gate / missing value |
| --- | --- | --- |
| Platforms | iOS | Confirm |
| Name | `AIC: Am I Cooked?` | Confirm name availability |
| Primary language | English (U.S.) | Confirm |
| Bundle ID | `com.binhnguyenhealth.aic` | Must first exist in Developer portal |
| SKU | `AIC-IOS-1` | **User must approve; SKU cannot be changed later** |
| User access | Full Access for a solo account | User decision; use Limited Access if other users exist |

### App Information

| Field | Recommended value | Gate |
| --- | --- | --- |
| Primary category | Reference | User confirmation |
| Secondary category | Lifestyle | Optional; user confirmation |
| Content Rights | Contains third-party City of Chicago content; select the attestation that necessary rights are held | **Do not attest until terms/legal review is complete** |
| License agreement | Apple's standard EULA | Confirm terms page does not require a custom EULA |
| Age rating | Questionnaire below; let Apple calculate | User attestation required |
| Made for Kids | No / Not Applicable | Confirm; do not select Kids |
| DSA status | Account holder must declare trader/non-trader accurately | Required if applicable; private legal/account decision |
| Regulated Medical Device | No | Confirm; app makes no medical claims |

### Pricing and Availability

| Field | Recommended value | Gate |
| --- | --- | --- |
| Price | Free | User decision |
| Tax category | App Store software / default applicable category | Confirm in current UI |
| Initial storefronts | United States only for the Chicago-first v1 | User decision; widen only after rights/regional checks |
| Pre-order | No | Confirm |
| Release method | Manual release | User decision; preserves a final post-approval gate |
| Phased release | Not applicable for first release | Confirm |

### iOS version 1.0.0

| Field | Source / value | Validation |
| --- | --- | --- |
| Version | `1.0.0` | Matches `MARKETING_VERSION` |
| App Store name | `distribution/app-store/metadata/en-US/name.txt` | 18 bytes including newline; under 30-character limit |
| Subtitle | `distribution/app-store/metadata/en-US/subtitle.txt` | 25 bytes including newline; under 30-character limit |
| Promotional text | `distribution/app-store/metadata/en-US/promotional_text.txt` | 113 bytes; under 170-character limit |
| Description | `distribution/app-store/metadata/en-US/description.txt` | 2,084 bytes; under 4,000-character limit; **remove optional username wording for guest-only** |
| Keywords | `distribution/app-store/metadata/en-US/keywords.txt` | 84 bytes; under 100-byte limit |
| Support URL | `https://aic-beta-info.binhnguyenhealth.workers.dev/support/` | HTTP 200 |
| Marketing URL | `https://aic-beta-info.binhnguyenhealth.workers.dev/` | HTTP 200 |
| Privacy Policy URL | `https://aic-beta-info.binhnguyenhealth.workers.dev/privacy/` | HTTP 200 |
| Screenshots | `distribution/app-store/screenshots/en-US/` | Three valid 1320×2868 PNGs; **replace screenshot 03 for guest-only** |
| Copyright | Recommended `2026 Binh Nguyen` | Legal owner must confirm exact name |
| App Review contact | Enter monitored name/email/phone only in App Store Connect | Missing; private user gate |
| Sign-in required | No | Guest-only build must prove this |
| Review notes | Start from `distribution/app-store/review-notes.md` | Remove all optional sign-in/account/username wording |
| Version release | Manually release | User gate |

For the first version, “What's New” is not required. Do not upload the current screenshot 03: it shows `@chi_builder`, “Show @chi_builder,” and account-linked copy that will not exist in guest-only v1.

## Privacy, age rating, export compliance, and rights

### App Privacy — guest-only v1

After the guest-only binary and its network behavior are independently verified:

- Tracking: **No**.
- Data collection: **No, we do not collect data from this app**.
- Privacy Policy URL: the verified URL above.
- User Privacy Choices URL: omit for guest-only, or use the public deletion/privacy page only if it accurately describes guest-only behavior.

Apple defines on-device-only processing as not “collected.” The app uses foreground precise location locally and does not transmit it. The checked-in `PrivacyInfo.xcprivacy` currently declares User ID and Other User Content because of the optional account design; revise the manifest for the guest-only binary and reconcile it with the App Privacy response. Do not claim “no data collected” while account requests remain reachable.

If production Sign in with Apple is retained instead, use `distribution/app-store/privacy-labels.md`: User ID and Other User Content, linked to the user, for App Functionality; no tracking; no location collection. That path is blocked until production E2E validation.

### Age Rating questionnaire

Use the current questionnaire and answer from the final binary. Recommended answers for the observed guest-only release:

- In-app controls: none.
- Unrestricted Web Access, UGC, Social Media, Messaging/Chat, Advertising: No.
- Mature or Suggestive Themes: **Infrequent** because Apple's current examples expressly include real-world crimes.
- Realistic Violence: None; the app shows category labels/counts, not violent depictions.
- Guns or Other Weapons: None unless final UI/data copy explicitly references them.
- Horror/Fear, profanity, alcohol/drugs, sexual content/nudity: None.
- Medical/Treatment and Health/Wellness: None.
- Gambling, simulated gambling, contests, loot boxes: None.
- Age Categories and Override: Not Applicable; not Made for Kids; no manual override unless the account holder deliberately chooses a higher rating.

Do not hard-code a final rating in source. Apple calculates global and regional ratings from the current questionnaire.

### Export compliance

The final Info.plist contains:

```text
ITSAppUsesNonExemptEncryption = NO
```

Recommended answer: the app uses no non-exempt encryption; its network encryption is provided by Apple's OS HTTPS stack. `ITSAppUsesNonExemptEncryption=NO` is appropriate only after verifying the final binary and all linked third-party libraries use no non-exempt cryptography. If that changes, stop and use Apple's export-compliance questionnaire/document workflow.

### Content Rights

The app ships derived aggregates from City of Chicago datasets `ijzp-q8t2`, `c7ck-438e`, and `igwz-8jzy`. Before answering Content Rights:

1. open each dataset's current official terms page;
2. save a dated evidence record;
3. confirm redistribution and the derived aggregate use are permitted; and
4. obtain legal review if the terms are ambiguous.

The repository's MIT license does not grant rights to third-party data.

## Exact release commands

Run these only after the guest-only patch, record creation, explicit provisioning authorization, and credential gate. Commands quote every path because the repository name contains `?`.

### 1. Establish immutable inputs

```bash
set -euo pipefail

export ROOT="$(git rev-parse --show-toplevel)"
export TEAM_ID="GJ96397VV7"
export BUNDLE_ID="com.binhnguyenhealth.aic"
export VERSION="1.0.0"
export BUILD="1"
export OUT="$HOME/Desktop/AIC-release-${VERSION}-${BUILD}"

test "$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)" != "HEAD"
test -z "$(git -C "$ROOT" status --porcelain)"
test ! -e "$OUT"
mkdir -p "$OUT"
```

The current research worktree is detached at `0446c4b`; create/use an intentional release branch before execution. Do not bypass the clean-tree check.

### 2. Preflight source and metadata

```bash
cd "$ROOT"

xcodebuild -version
xcodebuild -version -sdk iphoneos
xcodegen generate --spec ios/project.yml --project ios
git diff --exit-code -- ios/AIC.xcodeproj ios/AIC/Config/Info.plist

python3 -m unittest discover -s pipeline/tests -v
(cd services/account-worker && npm ci && npm run typecheck && npm test)
(cd ios && swift test)
python3 pipeline/verify_pack.py data/chicago_beta.sqlite data/chicago_beta.manifest.json
(cd data && shasum -a 256 -c chicago_beta.checksums.sha256)

plutil -lint \
  ios/AIC/Config/Info.plist \
  ios/AIC/Config/AIC.entitlements \
  ios/AIC/Resources/PrivacyInfo.xcprivacy

test "$(wc -c < distribution/app-store/metadata/en-US/keywords.txt | tr -d ' ')" -le 100
```

For guest-only v1, add repository tests that fail if Release exposes Sign in with Apple, username, account deletion, or account-service networking.

### 3. Inspect Release settings before portal access

```bash
xcodebuild \
  -project "$ROOT/ios/AIC.xcodeproj" \
  -scheme AIC \
  -configuration Release \
  -sdk iphoneos \
  -showBuildSettings \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  | tee "$OUT/release-build-settings.txt"

rg 'PRODUCT_BUNDLE_IDENTIFIER = com\.binhnguyenhealth\.aic$' "$OUT/release-build-settings.txt"
rg 'DEVELOPMENT_TEAM = GJ96397VV7$' "$OUT/release-build-settings.txt"
rg 'MARKETING_VERSION = 1\.0\.0$' "$OUT/release-build-settings.txt"
rg 'CURRENT_PROJECT_VERSION = 1$' "$OUT/release-build-settings.txt"
```

### 4. Archive with automatic signing

This command contacts Apple and may create/update signing resources. Run it only with explicit authorization. The App Store Connect key flags are optional if Xcode already has an authorized developer account; prefer the key form for reproducibility.

```bash
# Credential identifiers are not secrets, but keep the private key outside the repo.
export ASC_KEY_ID="<MISSING_KEY_ID>"
export ASC_ISSUER_ID="<MISSING_ISSUER_UUID>"
export ASC_KEY_PATH="$HOME/.private_keys/AuthKey_${ASC_KEY_ID}.p8"
test -s "$ASC_KEY_PATH"

xcodebuild \
  -project "$ROOT/ios/AIC.xcodeproj" \
  -scheme AIC \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$OUT/AIC.xcarchive" \
  -resultBundlePath "$OUT/AIC-archive.xcresult" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  archive | tee "$OUT/archive.log"
```

Do not add `-allowProvisioningDeviceRegistration`; a generic App Store archive does not require device registration.

### 5. Verify the archive before export

```bash
export APP="$OUT/AIC.xcarchive/Products/Applications/AIC.app"
test -d "$APP"

test "$(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")" = "$BUNDLE_ID"
test "$(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist")" = "$VERSION"
test "$(plutil -extract CFBundleVersion raw "$APP/Info.plist")" = "$BUILD"
test "$(plutil -extract ITSAppUsesNonExemptEncryption raw "$APP/Info.plist")" = "false"
test "$(find "$APP" -name PrivacyInfo.xcprivacy | wc -l | tr -d ' ')" = "1"

codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements "$OUT/archive-entitlements.plist" --xml "$APP"
plutil -lint "$OUT/archive-entitlements.plist"

# Guest-only hard gate: no Sign in with Apple entitlement.
if plutil -p "$OUT/archive-entitlements.plist" | rg -q 'com\.apple\.developer\.applesignin'; then
  echo 'STOP: Sign in with Apple entitlement remains in guest-only archive' >&2
  exit 1
fi

security cms -D -i "$APP/embedded.mobileprovision" > "$OUT/embedded-profile.plist"
test "$(plutil -extract TeamIdentifier.0 raw "$OUT/embedded-profile.plist")" = "$TEAM_ID"
test "$(plutil -extract Entitlements.application-identifier raw "$OUT/embedded-profile.plist")" = "$TEAM_ID.$BUNDLE_ID"

# No production account endpoint or account UI artifacts may be present in guest-only Release.
if strings "$APP/AIC" | rg -i 'aic-account-dev|Sign in with Apple|Delete account|public username'; then
  echo 'STOP: guest-only binary still contains account-release indicators; inspect before proceeding' >&2
  exit 1
fi
```

`strings` is a conservative tripwire, not proof by itself. Pair it with tests and physical-device network observation.

### 6. Export the IPA

```bash
cat > "$OUT/ExportOptions-export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST

plutil -lint "$OUT/ExportOptions-export.plist"

xcodebuild -exportArchive \
  -archivePath "$OUT/AIC.xcarchive" \
  -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions-export.plist" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  | tee "$OUT/export.log"

export IPA="$(find "$OUT/export" -maxdepth 1 -name '*.ipa' -print -quit)"
test -s "$IPA"
shasum -a 256 "$IPA" | tee "$OUT/ipa.sha256"
```

### 7. Validate, then upload exactly once

Validation is remote but non-publishing. Upload is an external mutation and requires a fresh explicit go-ahead.

```bash
xcrun altool --validate-app \
  -f "$IPA" \
  -t ios \
  --api-key "$ASC_KEY_ID" \
  --api-issuer "$ASC_ISSUER_ID" \
  --output-format json \
  | tee "$OUT/altool-validate.json"
```

**STOP.** Review the validation output, SHA-256, archive evidence, final metadata, and App Store Connect target record. Then, and only then, run:

```bash
xcrun altool --upload-app \
  -f "$IPA" \
  -t ios \
  --api-key "$ASC_KEY_ID" \
  --api-issuer "$ASC_ISSUER_ID" \
  --output-format json \
  | tee "$OUT/altool-upload.json"
```

The `.p8` must be at a location altool can resolve, conventionally `~/.private_keys/AuthKey_<KEY_ID>.p8`, or supplied through altool's supported key-path mechanism. Never place it in this repository or echo it.

An Xcode-only alternative is to copy the export plist, change `destination` to `upload`, and run `xcodebuild -exportArchive` with the same authentication key flags. Use one upload path, not both.

## Post-upload and physical-device gates

1. Wait for build `1` to finish processing; record all warnings and the delivery ID.
2. Confirm App Store Connect associated it with bundle ID `com.binhnguyenhealth.aic`, version `1.0.0`, build `1`.
3. Resolve export compliance if Apple did not infer it from Info.plist.
4. Add only this processed build to an internal TestFlight group.
5. Install it on a physical iPhone and test:
   - clean launch enters Home without account/sign-in;
   - location prompt appears only after **Scan My Area**;
   - denying location leaves the manual Chicago picker usable;
   - no background-location permission is requested;
   - score/receipt show `DATA THROUGH 2026-06-30 · NOT LIVE`;
   - receipt contains no username and no exact location metadata;
   - privacy/support/terms/methodology links open;
   - airplane-mode scan/manual-pin behavior remains local;
   - network observation shows no AIC account-service requests; and
   - the update-window/fail-closed behavior matches the manifest.
6. Reconcile the physical build against screenshots and review notes.
7. Select build `1`; complete App Review contact and notes.
8. Account holder explicitly authorizes **Add for Review**, then separately **Submit for Review**.

## Local automation and credential inventory

### Available

| Tool | Observed path / version | Use |
| --- | --- | --- |
| Xcode / `xcodebuild` | Xcode 26.6 (`17F113`) | build, archive, export, upload |
| `xcodegen` | `/opt/homebrew/bin/xcodegen` | regenerate project from `ios/project.yml` |
| `iTMSTransporter` | bundled in Xcode | alternate delivery transport |
| `altool` | bundled in Xcode | validate/upload IPA |
| `security`, `codesign`, `plutil` | macOS system tools | identity/profile/signature/plist inspection |
| `swift` | Xcode toolchain | package tests |
| Node/npm | Homebrew | Worker tests/typecheck |
| Python 3.13 | python.org framework | data pipeline tests |
| `jq`, `rg`, `shasum`, `git`, `gh` | installed | evidence and automation support |

### Missing or not established

- `fastlane` is not installed and there is no Fastfile/Deliver configuration.
- No purpose-built App Store Connect CLI is installed.
- No App Store Connect API key was found in the standard `~/private_keys`, `~/.private_keys`, or `~/.appstoreconnect/private_keys` directories.
- No relevant App Store Connect/Apple/Fastlane credential environment variable names were present.
- Xcode account authentication was not inspected; its availability is unverified.
- Four automatic App Store profiles exist for unrelated `info.holdmetoit.app*` identifiers; none covers AIC.
- No AIC provisioning profile exists.
- No physical device is attached.

Do not add Fastlane merely for this first submission. The native Xcode + altool path is already sufficient once credentials and the App Store record exist. Add API metadata automation only after the first record is created and the exact manual fields are stable.

## Asset verification evidence

| Asset | Result |
| --- | --- |
| App icon in asset catalog | 1024×1024 PNG, RGB, no alpha, structurally valid |
| `design/AppIcon-1024.png` | 1024×1024 PNG, RGB, no alpha, structurally valid |
| Screenshot 01 | 1320×2868 PNG; visually inspected; acceptable 6.9-inch portrait size |
| Screenshot 02 | 1320×2868 PNG; visually inspected; acceptable 6.9-inch portrait size |
| Screenshot 03 | 1320×2868 PNG; structurally valid but **semantically rejected for guest-only** |

Apple currently accepts one to ten screenshots and lists 1320×2868 as an accepted 6.9-inch portrait size. Alpha is present in the screenshot PNGs; App Store Connect accepts PNG screenshots, but the actual upload remains the definitive validation.

## Stop and rollback rules

- **Signing mismatch:** stop if the archive bundle ID, Team ID, profile application identifier, version, or build differs. Do not upload.
- **Guest-only mismatch:** stop if Sign in with Apple entitlement/UI, username/account copy, or account-service traffic remains. Fix source and create a new archive.
- **Metadata mismatch:** stop if screenshots, review notes, privacy labels, and binary behavior disagree.
- **Pack timing:** stop if review/release is unlikely before the update-window boundary without a refresh.
- **Portal ambiguity:** stop if the target record, provider, role, agreements, or bundle registration is uncertain.
- **Validation warnings:** classify every warning; do not treat a zero exit code as acceptance.
- **Duplicate upload:** build `1` is immutable once uploaded. If its binary is wrong, increment `CURRENT_PROJECT_VERSION` to `2`, rebuild from a clean tree, and leave build `1` unselected. Never overwrite an upload.
- **Bad TestFlight build:** remove it from groups/expire it in App Store Connect only with explicit account-holder authorization; preserve local logs and hashes.
- **Submission mistake:** use Remove from Review/Developer Reject only with explicit authorization; these are external state changes.
- **Local artifacts:** preserve the `.xcarchive`, IPA hash, result bundle, validation JSON, upload JSON, and processed-build warnings. Do not delete evidence during rollback.
- **Secrets:** if a credential appears in logs or Git, stop, revoke/rotate it through the account holder, and do not continue with that credential.

## Official Apple sources checked

- [Upcoming SDK minimum requirements](https://developer.apple.com/news/?id=ueeok6yw)
- [Add a new app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
- [Required, localizable, and editable properties](https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties/)
- [Platform version information and limits](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [Set an app age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating)
- [Age rating values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions)
- [Overview of export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
- [`ITSAppUsesNonExemptEncryption`](https://developer.apple.com/documentation/BundleResources/Information-Property-List/ITSAppUsesNonExemptEncryption)
- [Overview of publishing an app](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/overview-of-publishing-your-app-on-the-app-store)
- [Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)

## Final go/no-go checklist

Submission is **NO-GO** until every item below is true:

- [ ] Guest-only release patch merged and clean.
- [ ] Screenshot 03 and account-related metadata replaced.
- [ ] Full test suite and Release checks pass.
- [ ] App ID and App Store Connect record exist for `com.binhnguyenhealth.aic`.
- [ ] Agreements, role, DSA, pricing, availability, rights, and contact gates are complete.
- [ ] AIC provisioning succeeds under Team `GJ96397VV7`.
- [ ] Archive signature/profile/entitlements/version/privacy checks pass.
- [ ] IPA remote validation is clean or every warning is resolved.
- [ ] Account holder authorizes one upload.
- [ ] Build `1` processes without unresolved warnings.
- [ ] Physical-device TestFlight smoke test passes.
- [ ] Final metadata/privacy/age/export answers match the processed binary.
- [ ] Account holder authorizes Add for Review and Submit for Review.
