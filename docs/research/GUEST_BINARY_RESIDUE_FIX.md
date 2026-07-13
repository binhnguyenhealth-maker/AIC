# Guest Release identity residue removal

Date: 2026-07-12

## Outcome

The `GUEST_ONLY_V1` Release build no longer compiles the dormant account,
authentication, username, or session implementation into the app or its embedded
`AICCore` framework. The guest receipt also has no username field, username
visibility state, username copy, or username rendering branch.

This is a build-artifact guarantee, not only a runtime-navigation guarantee. The
non-guest Debug implementation remains in source for possible future use.

## Changes

- Propagated `GUEST_ONLY_V1` to the Release configurations for `AIC`, `AICCore`,
  and `AICTests` in both `project.yml` and the checked-in Xcode project.
- Limited the guest Release app model to `launching` and `guest` phases, with a
  guest-only startup path that does not construct or restore an account session.
- Excluded the account API, Apple nonce helper, Keychain session store,
  authentication/session models, username policy, authentication screen,
  username screen, and their account-specific tests from guest Release builds.
- Replaced guest Settings account language with on-device privacy language.
- Removed `username` from `CookedReceiptPayload` and removed the username and
  username-visibility inputs from receipt composition.
- Removed receipt username state, controls, rendering, and disclosures while
  retaining the neighborhood/city-only coarsening control, PNG renderer, and
  native share flow.
- Added `ios/scripts/verify_guest_release_binary.py`, which inspects the app and
  embedded framework with `strings`, `nm`, and `otool` and fails if dormant
  identity types, endpoints, frameworks, or user-facing account copy reappear.

## Verification

Normal Swift package tests retained non-guest behavior:

```text
swift test
Executed 46 tests, with 0 failures (0 unexpected)
```

Guest-mode Swift package tests compiled the account/username surface out:

```text
swift test -Xswiftc -DGUEST_ONLY_V1
Executed 44 tests, with 0 failures (0 unexpected)
```

A clean unsigned Release simulator build used isolated DerivedData and did not
launch a simulator:

```text
xcodebuild -project ios/AIC.xcodeproj -scheme AIC -configuration Release \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/aic-guest-full-clean-dd \
  CODE_SIGNING_ALLOWED=NO build
** BUILD SUCCEEDED **
```

The artifact regression passed against that fresh build:

```text
python3 ios/scripts/verify_guest_release_binary.py \
  /tmp/aic-guest-full-clean-dd/Build/Products/Release-iphonesimulator/AIC.app
guest Release identity check passed
```

As a negative control, the same script failed against the earlier receipt-only
Release artifact and identified `AccountAPI`, `AccountAPIProtocol`,
`SessionStoring`, `needsUsername`, `AuthSession`, `UsernamePolicy`, and
`UsernameValidation`. This confirms the regression distinguishes the old
dormant implementation from the cleaned build.

Manual inspection of the same binaries found no account/auth/username symbols,
account endpoints, `ASAuthorization` symbols, or `AuthenticationServices`
dependency.

## Intentional residual strings

- `ReceiptPrivacyAudit` retains the defensive encoded-key literals `username`,
  `account`, `account_id`, and `accountid`. These literals make the receipt
  privacy audit reject future identity fields and are not an account feature.
- `PackStatusClient` retains the generic Keychain attribute value `account` for
  its installation identifier. It is not a user account, login, or session.

The regression therefore forbids the dormant implementation's concrete types,
endpoints, framework dependency, and user-facing copy rather than forbidding a
generic English word used by unrelated defensive or Keychain code.

## Remaining release step

The simulator Release artifact proves the compile-time boundary. The final
signed device archive/IPA must still be rebuilt from this source and run through
the same binary regression before App Store submission. A non-guest Xcode
`build-for-testing` was not rerun during this pass because another task was
already running simultaneous Xcode builds in the shared workspace; the normal
Swift package suite is the current evidence that retained non-guest policy code
still compiles and passes.
