# Privacy retention and City notice resolution

Date: 2026-07-12
Scope: final App Store privacy disclosure and City of Chicago notice audit

## Outcome

Both release-audit questions are resolved without weakening the emergency
pack-withdrawal mechanism.

1. AIC conservatively declares Cloudflare request/network metadata as linked
   **Other Data Types**, used only for **App Functionality**, with tracking
   disabled. This declaration is present in the app privacy manifest, App Store
   answer sheet, review notes, and public privacy policy.
   The manifest uses Apple's exact `NSPrivacyCollectedDataTypeOtherDataTypes`
   identifier.
2. Developer-accessible Cloudflare Workers observability is explicitly
   disabled in `web/wrangler.jsonc`. The deployed worker reports no
   observability setting, `logpush=false`, and no tail consumers. This reduces
   access but does not justify claiming that Cloudflare never retains network
   data, so the conservative disclosure remains.
3. The ASCII apostrophe in the City notice is retained. Chicago's official TIF
   disclaimer publishes the exact sentence with `one's own risk`; the separate
   City narrative page HTML uses `one&rsquo;s own risk`. The two official pages
   differ only in punctuation encoding, so the repository's ASCII text is an
   exact official variant rather than a legal-notice omission.
4. The manifest declares `NSPrivacyAccessedAPICategorySystemBootTime` with
   reason `35F9.1` because the signed-status gate uses `systemUptime` only to
   measure elapsed time between on-device verification events. That value is
   stored only in this app's ThisDeviceOnly Keychain state and is not sent
   off-device.

## Decision basis

Apple defines collection as off-device transmission retained longer than
real-time request servicing and specifically says retained IP addresses must be
declared under the relevant data type. Cloudflare states that it processes End
User IP addresses and traffic-routing/system data and may create or retain
network/security data. Cloudflare's Workers Logs documentation also describes
multi-day retention when observability is enabled. AIC therefore does not rely
on the narrower no-retention exception.

Primary sources checked:

- Apple, App Privacy Details:
  <https://developer.apple.com/app-store/app-privacy-details/>
- Cloudflare, Privacy Policy:
  <https://www.cloudflare.com/policies/privacy/>
- Cloudflare, Workers Logs:
  <https://developers.cloudflare.com/workers/observability/logs/workers-logs/>
- City of Chicago, official TIF disclaimer:
  <https://webapps1.chicago.gov/ChicagoTif/disclaimer.html>
- City of Chicago, official data disclaimer:
  <https://www.chicago.gov/city/en/narr/foia/data_disclaimer.html>

## Deployment and readback evidence

Wrangler accepted the explicit observability-off configuration in a dry run,
then deployed worker version
`0e9689c6-572f-4988-8b46-3870acdedc5f`.

Post-deployment checks confirmed:

- the Cloudflare settings API returned no enabled observability setting,
  `logpush=false`, and no tail consumers;
- the live `/privacy/` response was byte-identical to
  `web/public/privacy/index.html`;
- the live signed pack-status response remained byte-identical to the canonical
  operations copy and retained the expected JSON and five-minute cache headers.

## Remaining responsibility

App Store Connect must use the answers in
`distribution/app-store/privacy-labels.md`. The operator should re-check
Cloudflare and Apple policies before future releases, especially after enabling
analytics, logging, authentication, purchases, or another network endpoint.
This engineering decision is deliberately conservative; it is not a substitute
for qualified legal advice.
