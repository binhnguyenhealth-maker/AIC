# App Privacy answers

These answers describe the guest-only AIC v1 binary. Apple may independently collect diagnostics under Apple's policies.

## Tracking

- Data used to track the user: **No**
- Data linked with third-party data for advertising: **No**

## Data collected by AIC

| App Store category | Collected | Linked | Purpose | Notes |
| --- | --- | --- | --- | --- |
| User ID | No | No | — | v1 has no account or sign-in feature |
| Other User Content | No | No | — | v1 has no account, username, or hosted content feature |
| Precise Location | No | No | — | Used only on-device for the immediate scan |
| Coarse Location | No | No | — | Neighborhood is derived on-device and not sent to AIC |
| Email Address | No | No | — | AIC does not retain Apple relay email even if Apple supplies it |
| Diagnostics | No | No | — | No third-party analytics or crash SDK in the app |
| Purchases | No | No | — | Payments are deferred |
| Other Data Types | Yes | Yes | App Functionality | Cloudflare may retain the request IP address and ordinary HTTP/TLS or security metadata while serving the fixed status file; no scan, coordinate, account, or device identifier is sent |

The final binary may fetch one fixed global signed pack-status file at launch or foreground, rate-limited to once per 15 minutes. It sends no city, coordinate, scan, account, device identifier, or installed-pack identifier. The static-file host processes and may retain the request IP address and ordinary HTTP/TLS or security metadata for delivery, reliability, and abuse/security operations. AIC disables developer-accessible Workers Logs and Logpush and uses no cookies, analytics, advertising identifiers, or personalization for this check. The table deliberately discloses **Other Data Types**, linked to the user, for **App Functionality** as the conservative answer because the provider's network-data retention can outlast real-time request servicing. It is not used for tracking.

Re-check these answers against the final binary and service schema immediately before submission. Any analytics, crash reporter, email retention, or server-side receipt feature changes the answers.

## Accounts

Not applicable to v1. The app does not create or access accounts and therefore has no account data to delete.
