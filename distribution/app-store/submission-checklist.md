# AIC App Store submission checklist

## Automated/source-ready items

- [x] iOS project generation succeeds
- [x] iOS Simulator build, install, and launch succeed in CI
- [x] Swift Package tests pass (24 tests)
- [x] App-hosted Simulator unit/privacy tests pass (46 tests)
- [x] Clean installs open the account-free scan flow
- [x] Bundled packs fail closed at the documented fresh-until boundary
- [x] Every generated score and receipt shows the exact source-through date and a not-live label
- [x] Release version is 1.0.0 (build 1)
- [x] Account and information service URLs respond over HTTPS
- [ ] Validate production Sign in with Apple, refresh, logout, and deletion end to end
- [x] Debug Simulator app contains one privacy manifest; Release archive/readback remains below
- [x] App icon and required screenshots are generated and visually inspected
- [x] Privacy policy URL returns HTTP 200
- [x] Support URL returns HTTP 200
- [x] App Store copy and review notes drafted
- [ ] Deploy and read back the updated production privacy, support, methodology, deletion, and terms pages

## Apple-account manual gates

- [x] Install Xcode 26.6 and an iOS 26.5 Simulator runtime
- [ ] Add the founder's Apple Developer team to Xcode
- [ ] Register the final bundle identifier and enable Sign in with Apple
- [ ] Create or select the App Store Connect app record
- [ ] Add the App Store Connect review contact and privacy-policy fields
- [ ] Confirm agreements, tax, and banking status do not block distribution
- [ ] Create a distribution certificate/profile or enable automatic signing
- [ ] Archive and validate a physical-device Release build
- [ ] Upload the archive and wait for App Store processing
- [ ] Add the processed build to an internal TestFlight group
- [ ] Install from TestFlight on a physical device and execute the smoke test
- [ ] Complete age rating, export compliance, content rights, and App Privacy forms
- [ ] Upload final device screenshots
- [ ] Submit the selected build for external TestFlight beta review or App Review

## Trust and data-release gates

- [ ] Complete independent statistical review of the current methodology and disclosures
- [ ] Complete qualified legal/privacy review of claims, terms, correction process, and Chicago data rights
- [ ] Verify the current City of Chicago source terms and retain a dated evidence record
- [ ] Establish and test an emergency pack correction/withdrawal path in addition to the local freshness cutoff
- [ ] Validate the update-window, update-due-soon, and scans-paused states in a final device build
- [ ] Assign an owner and calendar alert to refresh or withdraw the pack before `2026-08-07T00:00:00Z`

## Conservative form answers

- Export compliance: app uses only encryption provided by the operating system for HTTPS; confirm Apple's current exemption questions in App Store Connect.
- Advertising identifier / tracking: none.
- Background location: none.
- User-generated public hosting: none; receipts leave the app only through a user-selected iOS share destination.
- Content: historical crime categories without graphic imagery; review the current age-rating questionnaire rather than guessing a final rating in source control.
