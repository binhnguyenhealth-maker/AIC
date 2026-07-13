# Signed App Store IPA validation — 2026-07-12

## Outcome

**PASS for signing, package validation, and upload.** Xcode exported a fresh
signed App Store IPA for AIC 1.0.0 (build 2) from Git commit `159b830`. App
Store Connect accepted the upload and reported that the package is processing.
App Store Connect forms and TestFlight installation remain separate gates.

## Candidate

- IPA: `build/export-app-store-final-2/AIC.ipa`
- SHA-256: `2f59a9aad970a2948ab0bb514d837882e8f31dbaa7b1a4d2f587e7dfc6341fd5`
- Source commit: `159b830` (`release: bump App Store build to 2`), including
  the release hardening in `98dc155`
- Bundle identifier: `com.binhnguyenhealth.aic`
- Version/build: `1.0.0` / `2`
- Architecture: `arm64`
- Minimum iOS: `17.0`

## Signing evidence

- `codesign --verify --deep --strict` passed.
- Authority: `Apple Distribution: BINH CONG NGUYEN (GJ96397VV7)`.
- Team identifier: `GJ96397VV7`.
- Signed binary entitlements are limited to the application identifier, team
  identifier, App Store beta reporting, and `get-task-allow = false`.
- The signed binary has no Sign in with Apple entitlement.
- Xcode-managed App Store profile:
  `iOS Team Store Provisioning Profile: com.binhnguyenhealth.aic`.
- Profile UUID: `be065392-0f36-4c4d-b598-53da759e2dbf`.
- Profile expiration: `2027-07-13T00:40:43Z`.

## Package readback

- Production bundle identifier and version/build match the submission target.
- `ITSAppUsesNonExemptEncryption` is `false`.
- The privacy, support, terms, methodology, and fixed pack-status HTTPS URLs are
  present in the final Info.plist.
- The signed app contains the privacy manifest, Chicago pack, schema, and signed
  pack-status bootstrap.
- The Release privacy manifest declares linked Other Data for App Functionality,
  with tracking disabled and no tracking domains.
- The required-reason declarations are exactly UserDefaults `CA92.1` and System
  Boot Time `35F9.1`.
- The automated guest Release validator passed against the signed app and found
  no account, username, authentication endpoint, or Sign in with Apple residue.

## Commands

```sh
xcodebuild -project ios/AIC.xcodeproj -scheme AIC -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/AIC-final-1.0.0-2.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive

xcodebuild -exportArchive \
  -archivePath build/AIC-final-1.0.0-2.xcarchive \
  -exportPath build/export-app-store-final-2 \
  -exportOptionsPlist build/ExportOptions-AppStore.plist \
  -allowProvisioningUpdates

codesign --verify --deep --strict /tmp/aic-signed-verify/Payload/AIC.app
codesign -d --entitlements :- /tmp/aic-signed-verify/Payload/AIC.app
python3 ios/scripts/verify_guest_release_binary.py \
  /tmp/aic-signed-verify/Payload/AIC.app

xcodebuild -exportArchive \
  -archivePath build/AIC-final-1.0.0-2.xcarchive \
  -exportPath build/upload-app-store-final-2 \
  -exportOptionsPlist build/ExportOptions-AppStore-Upload.plist \
  -allowProvisioningUpdates
# Upload succeeded; uploaded package is processing.
```
