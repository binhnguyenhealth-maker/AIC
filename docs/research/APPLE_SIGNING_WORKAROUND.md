# Apple signing workaround audit — 2026-07-12

## Verdict

**GO** for the signing, entitlement, and local package gate at release candidate
commit `315e07ba2e7b6a09cd1eda760c7b42238e9f975a`.

The exported IPA independently matches the candidate documented in
`SIGNED_IPA_VALIDATION_2026-07-12.md`. Its app and embedded framework pass
strict signature verification, the app is signed by an Apple Distribution
certificate authorized by the embedded App Store profile, and the executable
requests only the expected distribution entitlements. No local
signing/entitlement/package blocker remains.

This verdict is a GO to the next external gate, not evidence of App Store
acceptance. Upload, Apple server-side package processing, App Store Connect
forms, and TestFlight installation were not performed.

## Candidate and direct evidence

- Audited commit: `315e07ba2e7b6a09cd1eda760c7b42238e9f975a`
  (`main` resolved to the same commit at audit start).
- IPA: `/Users/binhnguyen/Am i cooked?/build/export-app-store/AIC.ipa`
- IPA SHA-256:
  `0b51e253572543a8f7916a9517f280b067150f55a023de0c25b99b7794502a23`
- `codesign --verify --deep --strict` passed on the app; strict verification
  also passed separately on `AICCore.framework`.
- App signature authority: `Apple Distribution: BINH CONG NGUYEN
  (GJ96397VV7)`; signed team: `GJ96397VV7`.
- The leaf signing certificate is one of the two developer certificates in the
  embedded provisioning profile. It was valid from `2026-07-13T00:36:51Z`
  through `2027-07-13T00:36:50Z`; the package signing time falls inside that
  interval.
- Embedded profile: `iOS Team Store Provisioning Profile:
  com.binhnguyenhealth.aic`, UUID
  `be065392-0f36-4c4d-b598-53da759e2dbf`, team `GJ96397VV7`, expiration
  `2027-07-13T00:40:43Z`.
- Signed executable entitlements are exactly:
  `application-identifier=GJ96397VV7.com.binhnguyenhealth.aic`,
  `beta-reports-active=true`,
  `com.apple.developer.team-identifier=GJ96397VV7`, and
  `get-task-allow=false`.
- The signed executable does **not** contain
  `com.apple.developer.applesignin`, keychain groups, push, iCloud, associated
  domains, or other application capabilities.
- Package readback: bundle ID `com.binhnguyenhealth.aic`, version `1.0.0`,
  build `1`, minimum iOS `17.0`, arm64 executable, and
  `ITSAppUsesNonExemptEncryption=false`.
- The IPA contains one application, its signed `AICCore.framework`, privacy
  manifest, Chicago database/schema, pack-status bootstrap, and exported
  symbols. No unexpected app extension or additional executable was found.
- `ExportOptions-AppStore.plist` uses method `app-store-connect`, destination
  `export`, automatic signing, team `GJ96397VV7`, no automatic version/build
  change, Swift symbol stripping, and symbol upload enabled.
- Release project settings resolve automatic signing, team `GJ96397VV7`, app
  bundle ID `com.binhnguyenhealth.aic`, version/build `1.0.0`/`1`, and
  `GUEST_ONLY_V1`. The source `AIC.entitlements` dictionary is empty and the
  Release target has no resolved `CODE_SIGN_ENTITLEMENTS` path.

## Blocker table

| ID | Severity | Blocking? | Finding and direct evidence | Exact fix / disposition |
| --- | --- | --- | --- | --- |
| S-01 | INFO | No | The embedded provisioning profile permits `com.apple.developer.applesignin` and keychain access groups, but `codesign -d --entitlements :-` proves the signed app requests neither. Strict signature verification passes and the application identifier/team match the profile. | No package fix is required. Optional profile hygiene is to disable Sign in with Apple for this App ID in the Apple Developer portal and re-export a later build, but that account mutation was not authorized and is not required for this IPA's signed entitlement set. |
| S-02 | UNVERIFIED | Not a local blocker | No upload or Apple server-side validation was performed, so App Store processing acceptance and TestFlight installability have no direct evidence in this audit. | With explicit upload authority, upload this exact SHA-256 candidate and require successful App Store processing plus a TestFlight install/launch check. Do not rebuild between this audit and upload. |

No Critical, High, Medium, or Low signing/entitlement/package blocker was
found.

## Exact form answers supported by this package

- **Sign in with Apple used by this app/version:** `No`. The signed executable
  has no Sign in with Apple entitlement.
- **Uses non-exempt encryption:** `No`. The packaged Info.plist sets
  `ITSAppUsesNonExemptEncryption` to `false`.
- **Bundle ID:** `com.binhnguyenhealth.aic`.
- **Version / build:** `1.0.0` / `1`.

These answers describe the audited binary only. They do not replace answers to
other App Store Connect legal, privacy, content-rights, or export questions.

## Commands and checks performed

```sh
git status --short --branch
git rev-parse HEAD
git rev-parse main
git show -s --format='%H%n%an <%ae>%n%s' 315e07b
git diff --stat 315e07b^ 315e07b

shasum -a 256 '/Users/binhnguyen/Am i cooked?/build/export-app-store/AIC.ipa'
unzip -q '/Users/binhnguyen/Am i cooked?/build/export-app-store/AIC.ipa' -d "$AUDIT_DIR"
codesign --verify --deep --strict --verbose=2 "$AUDIT_DIR/Payload/AIC.app"
codesign -dvvv "$AUDIT_DIR/Payload/AIC.app"
codesign -d --entitlements :- "$AUDIT_DIR/Payload/AIC.app"
codesign --verify --strict --verbose=2 \
  "$AUDIT_DIR/Payload/AIC.app/Frameworks/AICCore.framework"
codesign -dvv "$AUDIT_DIR/Payload/AIC.app/Frameworks/AICCore.framework"

security cms -D \
  -i "$AUDIT_DIR/Payload/AIC.app/embedded.mobileprovision" \
  > "$AUDIT_DIR/profile.plist"
/usr/libexec/PlistBuddy -x -c 'Print :Entitlements' "$AUDIT_DIR/profile.plist"
codesign -d --extract-certificates="$AUDIT_DIR/codesign-cert" \
  "$AUDIT_DIR/Payload/AIC.app"
openssl x509 -inform DER -in "$AUDIT_DIR/codesign-cert0" \
  -noout -subject -issuer -dates
# Compared codesign-cert0 byte-for-byte with DeveloperCertificates in profile.plist.

/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  "$AUDIT_DIR/Payload/AIC.app/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$AUDIT_DIR/Payload/AIC.app/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "$AUDIT_DIR/Payload/AIC.app/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' \
  "$AUDIT_DIR/Payload/AIC.app/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' \
  "$AUDIT_DIR/Payload/AIC.app/Info.plist"
file "$AUDIT_DIR/Payload/AIC.app/AIC"
find "$AUDIT_DIR" -maxdepth 3 -print
plutil -p '/Users/binhnguyen/Am i cooked?/build/ExportOptions-AppStore.plist'

security find-identity -v -p codesigning
xcodebuild -project ios/AIC.xcodeproj -scheme AIC \
  -configuration Release -showBuildSettings
xcodebuild -version
```

The audit used Xcode 26.6 (build 17F113). No build, archive, re-sign, portal
change, upload, or account mutation was performed.

## Remaining UNVERIFIED items

- App Store Connect upload acceptance and server-side package processing.
- TestFlight installation, first launch, and device execution of this exact IPA.
- App Store Connect form state, agreements, tax/banking state, and review
  metadata acceptance.
- Certificate/profile revocation status at the future time of upload; this
  audit proves local validity and matching material at audit time only.
