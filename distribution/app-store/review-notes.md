# App Review notes

## Purpose and limitation

AIC is a Chicago-only historical-data product. The primary result contains this limitation:

> Cooked Score is a historical data index that compares reported-incident concentration around this location with eligible Chicago comparison locations. It is not a live safety assessment or personal-risk prediction.

The app does not claim live danger, personal victimization probability, causality, or guaranteed safety.

Every generated score displays **DATA THROUGH [exact date] · NOT LIVE** next to the score. The same exact source-through date and not-live label appear on the rendered Cooked Receipt. Source records dated after that date are not included, and later additions or revisions may also be absent. The bundled pack defines a separate update-window cutoff; at or after that cutoff, the scan engine fails closed and produces no score. Passing that check means only that the pack remains within its configured update window, not that the underlying source is complete, unrevised, or live.

The displayed count and category breakdown are privacy-coarsened estimates. The bundled pack assigns each eligible source record to one non-overlapping 250-meter cell and independently rounds each supported category to the nearest five. It contains no incident points, source IDs, exact or residual cell totals, addresses, or timestamps. The app area-weights those released bands for an exact 500-meter radius (shown as about 0.3 miles / 1,640 feet in U.S. mode) and compares the estimate with Chicago reference locations produced by the same method. The Settings unit choice changes labels only, never the calculation.

## Review path

1. Launch the app. Without a stored signed-in session, it opens the account-free Home screen directly.
2. Tap **Scan My Area**. This is the first point at which location permission is requested.
3. Alternatively, deny permission and choose **Choose another spot** to use the offline Chicago manual-pin picker.
4. Inspect the Cooked Score, Chicago percentile, leading category, estimated incident count, and the adjacent **DATA THROUGH [exact date] · NOT LIVE** disclosure.
5. Open **Cooked Receipt**, confirm that it repeats the exact data-through date and not-live label, independently hide the neighborhood, and invoke the native share sheet. If signed in, the public username is an additional independent visibility control.
6. Cancel the share sheet; AIC uploads no receipt.
7. Settings offers optional Sign in with Apple for account and public-username features. Signed-in settings also contain logout and account deletion.

## Location privacy

Normal current-location scans and manual pins are processed on-device against a bundled SQLite data pack. AIC does not transmit scan coordinates, addresses, routes, scan-derived geographic cells, or scan history to its account service. The application does not declare or request background-location access. Receipt images contain no precise location or EXIF/GPS metadata.

## Reviewer access

AIC's scan and report flow works without an account. Sign in with Apple is the only optional authentication method; no password or reviewer credential is required. The production service audience and Sign in with Apple entitlement must match the submitted bundle identifier.

## Contacts

Use the App Store Connect review contact fields for a monitored individual email and telephone number. Do not place private founder contact information in this repository.
