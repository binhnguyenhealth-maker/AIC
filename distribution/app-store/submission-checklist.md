# AIC beta submission checklist

## Automated/source-ready items

- [x] iOS project generation succeeds
- [x] iOS Simulator build, install, and launch succeed in CI
- [x] Swift Package and 27 app-hosted unit/privacy tests pass
- [x] Release configuration points to the deployed account service
- [x] Debug Simulator app contains one privacy manifest; Release archive/readback remains below
- [ ] App icon and required screenshots are generated and visually inspected
- [x] Privacy policy URL returns HTTP 200
- [x] Support URL returns HTTP 200
- [x] App Store copy and review notes drafted

## Apple-account manual gates

- [ ] Install full Xcode and an iOS 17+ simulator runtime
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

## Conservative form answers

- Export compliance: app uses only encryption provided by the operating system for HTTPS; confirm Apple's current exemption questions in App Store Connect.
- Advertising identifier / tracking: none.
- Background location: none.
- User-generated public hosting: none in this beta; receipts leave the app only through a user-selected iOS share destination.
- Content: historical crime categories without graphic imagery; review the current age-rating questionnaire rather than guessing a final rating in source control.
