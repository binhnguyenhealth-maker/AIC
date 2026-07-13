# Data Sources and Attribution

AIC's Chicago beta is built from public datasets published through the City of
Chicago Data Portal. The application ships a derived aggregate pack, not the
source incident records.

## Sources

| Dataset | Portal ID | Purpose |
| --- | --- | --- |
| Crimes — 2001 to Present | [`ijzp-q8t2`](https://data.cityofchicago.org/d/ijzp-q8t2) | Historical reported-incident inputs |
| Chicago Police Department IUCR Codes | [`c7ck-438e`](https://data.cityofchicago.org/d/c7ck-438e) | Frozen category mapping and validation |
| Boundaries — Community Areas | [`igwz-8jzy`](https://data.cityofchicago.org/d/igwz-8jzy) | Chicago/community-area geometry |

The exact source URLs, retrieval timestamps, source update epochs, queries, row
counts, and snapshot hashes for a release are recorded in
[`data/chicago_beta.manifest.json`](data/chicago_beta.manifest.json).

## Transformation

The pipeline:

1. validates the selected period and frozen IUCR mapping;
2. rejects malformed, out-of-domain, or excessively complex boundary data;
3. assigns each eligible source event to one non-overlapping 250 m cell and one
   supported category;
4. rounds each category independently to the nearest five;
5. removes source records and exact source fields before writing the released
   SQLite pack;
6. verifies the final schema, privacy constraints, deterministic hashes, and
   Swift/Python parity fixtures.

The released pack contains no incident IDs, coordinates, addresses, blocks,
dates, timestamps, case numbers, exact cell totals, or residuals.

## Limitations

Chicago Police Department data reflects reported incidents, is preliminary,
may be revised, may contain errors or omissions, and does not capture
unreported incidents. Source-map locations are approximate. AIC's derived
score is descriptive historical context, not a live safety assessment or a
prediction of personal risk.

## Terms

The source datasets link to the City of Chicago Data Portal terms of use. Users
who redistribute or rebuild the data should review the current terms shown on
each dataset page. AIC's MIT license applies to this repository's software; it
does not replace or expand rights attached to third-party source data.

City-required derivative-application notice:

> This site provides applications using data that has been modified for use
> from its original source, www.cityofchicago.org, the official website of the
> City of Chicago. The City of Chicago makes no claims as to the content,
> accuracy, timeliness, or completeness of any of the data provided at this
> site. The data provided at this site is subject to change at any time. It is
> understood that the data provided at this site is being used at one's own
> risk.
