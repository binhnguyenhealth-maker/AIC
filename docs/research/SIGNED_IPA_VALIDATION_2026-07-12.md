# Signed App Store IPA validation — 2026-07-12

## Outcome

**PASS for local signing and package validation.** Xcode exported a signed App
Store IPA for AIC 1.0.0 (build 1). Upload, App Store processing, App Store
Connect forms, and TestFlight installation remain separate gates.

## Candidate

- IPA: `build/export-app-store/AIC.ipa`
- SHA-256: `0b51e253572543a8f7916a9517f280b067150f55a023de0c25b99b7794502a23`
- Bundle identifier: `com.binhnguyenhealth.aic`
- Version/build: `1.0.0` / `1`
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
- The Release privacy manifest declares no collected data and only the required
  UserDefaults API reason.

## Commands

```sh
xcodebuild -project ios/AIC.xcodeproj -scheme AIC -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData-AIC-device \
  -archivePath build/AIC-unsigned-1.0.0-1.xcarchive \
  DEVELOPMENT_TEAM=GJ96397VV7 CODE_SIGNING_ALLOWED=NO archive

xcodebuild -exportArchive \
  -archivePath build/AIC-unsigned-1.0.0-1.xcarchive \
  -exportPath build/export-app-store \
  -exportOptionsPlist build/ExportOptions-AppStore.plist \
  -allowProvisioningUpdates

codesign --verify --deep --strict build/ipa-inspect/Payload/AIC.app
codesign -d --entitlements :- build/ipa-inspect/Payload/AIC.app
```
