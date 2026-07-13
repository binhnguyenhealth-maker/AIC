# Guest-only App Store v1 result

## Summary

The iOS Release configuration is now guest-only. `GUEST_ONLY_V1` is set only
for Release builds, where startup goes directly to the guest flow, account and
Sign in with Apple views are compiled out, and `AppModel` neither creates an
account API client nor restores or refreshes an account session. The app target
has no Sign in with Apple capability or entitlement and no account-service or
account-deletion URL in its generated `Info.plist`.

The unreleased account implementation remains available in source and in Debug
builds for possible later work. Re-enabling it requires an explicit release
decision, production service configuration, Apple capability setup, privacy
review, and end-to-end account testing.

App Store metadata, App Review notes, App Privacy answers, public privacy/help
copy, and the README now describe the no-account v1. The privacy manifest
declares no collected data types.

This work does not submit, upload, deploy, sign, or archive the app.

## Changed files

- `README.md`
- `distribution/app-store/metadata/en-US/description.txt`
- `distribution/app-store/privacy-labels.md`
- `distribution/app-store/review-notes.md`
- `distribution/app-store/submission-checklist.md`
- `ios/project.yml`
- `ios/AIC.xcodeproj/project.pbxproj`
- `ios/AIC/App/AICApp.swift`
- `ios/AIC/App/AppModel.swift`
- `ios/AIC/Config/AIC.entitlements`
- `ios/AIC/Config/Info.plist`
- `ios/AIC/Features/Authentication/AuthScreen.swift`
- `ios/AIC/Features/Authentication/UsernameScreen.swift`
- `ios/AIC/Features/Home/HomeScreen.swift`
- `ios/AIC/Features/Settings/SettingsScreen.swift`
- `ios/AIC/Resources/PrivacyInfo.xcprivacy`
- `ios/Tests/AICAppTests/PrivacyConfigurationTests.swift`
- `web/public/account-deletion/index.html`
- `web/public/methodology/index.html`
- `web/public/privacy/index.html`
- `web/public/support/index.html`
- `web/public/terms/index.html`
- `docs/research/GUEST_ONLY_V1_RESULT.md`

## Validation evidence

Performed on July 12, 2026 with Xcode 26.6 and the iOS 26.5 simulator SDK.

1. Project generation:

   ```text
   xcodegen generate --spec ios/project.yml --project ios
   Created project at .../ios/AIC.xcodeproj
   ```

2. Generated Release settings:

   ```text
   SWIFT_ACTIVE_COMPILATION_CONDITIONS = GUEST_ONLY_V1
   ```

   The generated project contains no `CODE_SIGN_ENTITLEMENTS`, Sign in with
   Apple system capability, account URL key, or dev Worker URL.

3. Swift package tests:

   ```text
   swift test --package-path ios
   Executed 31 tests, with 0 failures
   ```

4. Generic unsigned Release simulator build:

   ```text
   xcodebuild -project ios/AIC.xcodeproj -target AIC \
     -configuration Release -sdk iphonesimulator \
     SYMROOT=/tmp/aic-guest-v1-build \
     OBJROOT=/tmp/aic-guest-v1-obj \
     CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO build
   ** BUILD SUCCEEDED **
   ```

5. Built app inspection:

   - `Info.plist` contains neither `AIC_API_BASE_URL` nor
     `AIC_ACCOUNT_DELETION_URL`.
   - Exactly one `PrivacyInfo.xcprivacy` is present.
   - `NSPrivacyCollectedDataTypes` is an empty array.
   - The executable contains none of the checked Sign in with Apple, account
     endpoint, dev Worker, account-service, or account UI strings.
   - The executable does not link `AuthenticationServices.framework`.
   - The generated project and source configuration contain no Sign in with
     Apple entitlement/capability or account endpoint residue.

6. App-hosted test bundle compilation:

   ```text
   xcodebuild -project ios/AIC.xcodeproj -target AICTests \
     -configuration Debug -sdk iphonesimulator -arch arm64 \
     ONLY_ACTIVE_ARCH=YES \
     SYMROOT=/tmp/aic-guest-v1-test-build \
     OBJROOT=/tmp/aic-guest-v1-test-obj \
     CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO build
   ** BUILD SUCCEEDED **
   ```

   The hosted `xcodebuild test` action was attempted against the existing
   booted iPhone 17 Pro simulator, but local Xcode made no progress beyond build
   description for more than two minutes. It was stopped under the retry
   discipline. Runtime execution of the app-hosted tests is therefore
   **UNVERIFIED** in this worktree; all test sources do compile.

7. Configuration and formatting checks:

   - `plutil -lint` passed for source and built `Info.plist`, entitlements, and
     privacy manifests.
   - `git diff --check` passed.

The only build warnings were Xcode's expected App Intents metadata message for
a target with no App Intents dependency.

## Residual risks and manual gates

- A signed device Release archive was not produced because this worktree has no
  Apple Developer team configured and signing/account actions were out of
  scope. Reinspect the archive's effective entitlements and embedded privacy
  manifest before upload.
- The public files under `web/public` were changed locally but not deployed.
  Deploy them and read back the live privacy, support, methodology, account,
  and terms URLs before App Review.
- App Store Connect privacy answers and review notes were updated in source only;
  enter and verify them manually in App Store Connect.
- Run the full hosted test suite and a physical-device/TestFlight smoke test in
  the final integration checkout.
- The simulator Release uses the repository's simulator-only showcase bundle
  identifier override. Confirm the signed device archive uses
  `com.binhnguyenhealth.aic`.
- Account code intentionally remains in the repository. Do not remove the
  `GUEST_ONLY_V1` Release condition or restore account plist/capability settings
  for v1.

## Cherry-pick and integration guidance

Cherry-pick the single guest-only v1 commit reported with this result. The most
likely conflict surface is `ios/project.yml` and its generated
`ios/AIC.xcodeproj/project.pbxproj`, especially if emergency-status work also
changed build settings or source membership.

Resolve `ios/project.yml` as the source of truth, preserving both the emergency
status changes and these guest-only invariants:

- Release includes `GUEST_ONLY_V1`.
- There is no Sign in with Apple entitlement or system capability.
- There is no account API/deletion key or endpoint in the app plist/settings.

Then regenerate rather than hand-merging the project file:

```bash
xcodegen generate --spec ios/project.yml --project ios
```

Repeat the Release build and built-bundle inspections above after conflict
resolution. Do not cherry-pick or restore an older generated project file over
the resolved `project.yml` output.
