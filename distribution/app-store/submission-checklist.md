# AIC App Store submission checklist

## Automated/source-ready items

- [x] iOS project generation succeeds
- [x] iOS Simulator build, install, and launch succeed in CI
- [x] Swift Package tests pass in normal (48 tests) and guest Release mode (46 tests)
- [x] App-hosted Simulator unit/privacy tests pass (68 tests)
- [x] Clean installs open the guest-only scan flow
- [x] Bundled packs fail closed at the documented fresh-until boundary
- [x] Every generated score and receipt shows the exact source-through date and a not-live label
- [x] Release version is 1.0.0 (build 2)
- [x] Release source has no account endpoint, account UI, or Sign in with Apple entitlement
- [x] Rebuilt signed App Store IPA contains one privacy manifest declaring only linked Other Data for App Functionality, with tracking disabled
- [x] App icon and required screenshots are generated and visually inspected
- [x] Privacy policy URL returns HTTP 200
- [x] Support URL returns HTTP 200
- [x] App Store copy and review notes drafted
- [x] Deploy and read back the updated guest-only privacy, support, methodology, deletion, and terms pages

## Apple-account manual gates

- [x] Install Xcode 26.6 and an iOS 26.5 Simulator runtime
- [x] Add the founder's Apple Developer team to Xcode
- [x] Register the final bundle identifier (Sign in with Apple is not enabled in the signed v1 binary)
- [x] Create the App Store Connect app record (Apple ID `6790261791`)
- [ ] Add the App Store Connect review contact and privacy-policy fields
- [x] Confirm the active Free Apps Agreement permits free distribution; paid-app tax and banking setup is not required for this free v1
- [x] Create a distribution certificate/profile or enable automatic signing
- [x] Archive a generic production-device Release build and export a signed App Store IPA
- [x] Upload build 2 to App Store Connect
- [x] Wait for App Store processing to complete (build 2 is Ready to Submit)
- [ ] Add the processed build to an internal TestFlight group
- [ ] Install from TestFlight on a physical device and execute the smoke test
- [ ] Complete age rating, export compliance, content rights, and App Privacy forms
- [x] Upload the three final 6.9-inch screenshots
- [ ] Submit the selected build for external TestFlight beta review or App Review

## Trust and data-release gates

- [ ] Complete independent statistical review of the current methodology and disclosures
- [ ] Complete qualified legal/privacy review of claims, terms, correction process, and Chicago data rights
- [x] Verify the current City of Chicago source terms and retain a dated evidence record
- [x] Establish and test an emergency pack correction/withdrawal path in addition to the local freshness cutoff
- [ ] Validate the update-window, update-due-soon, and scans-paused states in a final device build
- [ ] Assign an owner and calendar alert to refresh or withdraw the pack before `2026-08-07T00:00:00Z`

## Conservative form answers

- Export compliance: app uses only encryption provided by the operating system for HTTPS; confirm Apple's current exemption questions in App Store Connect.
- Advertising identifier / tracking: none.
- Background location: none.
- User-generated public hosting: none; receipts leave the app only through a user-selected iOS share destination.
- Content: historical crime categories without graphic imagery; review the current age-rating questionnaire rather than guessing a final rating in source control.
