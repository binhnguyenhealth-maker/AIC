# App Review notes

## Purpose and limitation

AIC is a Chicago-only descriptive statistics beta. The primary result contains this limitation:

> Cooked Score Beta compares historical reported-incident concentration around this location with eligible Chicago comparison locations. It is not a live safety assessment or personal-risk prediction.

The app does not claim live danger, personal victimization probability, causality, or guaranteed safety.

The displayed count and category breakdown are privacy-coarsened estimates. The bundled pack assigns each eligible source record to one non-overlapping 250-metre cell and independently rounds each supported category to the nearest five. It contains no incident points, source IDs, exact or residual cell totals, addresses, or timestamps. The app area-weights those released bands for a fixed 500-metre circle and compares the estimate with Chicago reference locations produced by the same method.

## Review path

1. Launch the app and use Sign in with Apple.
2. Accept or edit the suggested unique username.
3. Tap **Scan Me**. This is the first point at which location permission is requested.
4. Alternatively, deny permission and choose a point with the offline Chicago manual-pin picker.
5. Inspect the Cooked Score, Chicago percentile, leading category, source-through date, estimated incident count, and historical-data limitation.
6. Open **Cooked Receipt**, independently hide the username and/or neighborhood, and invoke the native share sheet.
7. Cancel the share sheet; AIC uploads no receipt.
8. Account settings contain logout and account deletion.

## Location privacy

Normal current-location scans and manual pins are processed on-device against a bundled SQLite data pack. AIC does not transmit scan coordinates, addresses, routes, scan-derived geographic cells, or scan history to its account service. The application does not declare or request background-location access. Receipt images contain no precise location or EXIF/GPS metadata.

## Reviewer access

Sign in with Apple is the only authentication method. No password or reviewer credential is required. The production service audience and Sign in with Apple entitlement must match the submitted bundle identifier.

## Contacts

Use the App Store Connect review contact fields for a monitored individual email and telephone number. Do not place private founder contact information in this repository.
