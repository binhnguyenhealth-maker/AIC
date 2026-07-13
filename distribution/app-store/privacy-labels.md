# App Privacy answers

These answers describe AIC's own app and minimal account service. Apple may independently collect diagnostics under Apple's policies.

## Tracking

- Data used to track the user: **No**
- Data linked with third-party data for advertising: **No**

## Data collected by AIC

| App Store category | Collected | Linked | Purpose | Notes |
| --- | --- | --- | --- | --- |
| User ID | Yes | Yes | App functionality | Only when the user opts into an account; keyed hash of the Sign in with Apple subject mapped to an internal account ID |
| Other User Content | Yes | Yes | App functionality | Optional user-chosen public username for signed-in accounts |
| Precise Location | No | No | — | Used only on-device for the immediate scan |
| Coarse Location | No | No | — | Neighborhood is derived on-device and not stored by the account service |
| Email Address | No | No | — | AIC does not retain Apple relay email even if Apple supplies it |
| Diagnostics | No | No | — | No third-party analytics or crash SDK in the app |
| Purchases | No | No | — | Payments are deferred |

Re-check these answers against the final binary and service schema immediately before submission. Any analytics, crash reporter, email retention, or server-side receipt feature changes the answers.

## Account deletion

Deletion is initiated in the app and, after fresh Apple reauthentication, hard-deletes the account, username, Apple credential, proof, and all sessions. A keyed anti-race marker remains for 24 hours. Apple authorization tokens still awaiting revocation may be retained encrypted under random, account-unlinked outbox IDs for at most 20 attempts or 30 days. The UI must not require visiting the support site.
