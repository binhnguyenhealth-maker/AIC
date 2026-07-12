# Chicago beta data pack

This standard-library-only pipeline builds the compact, read-only Chicago pack
used by the AIC beta.

Official inputs:

- City of Chicago, **Crimes - 2001 to Present**, Socrata dataset
  [`ijzp-q8t2`](https://data.cityofchicago.org/d/ijzp-q8t2).
- Chicago Police Department **IUCR Codes**, Socrata dataset
  [`c7ck-438e`](https://data.cityofchicago.org/d/c7ck-438e).
- City of Chicago, **Boundaries - Community Areas**, Socrata dataset
  [`igwz-8jzy`](https://data.cityofchicago.org/d/igwz-8jzy).

The default build discovers the newest selected-category source record, drops
the still-changing calendar month containing that record, and downloads the 12
complete months immediately before it. The ignored build-only incident snapshot
retains `id`, occurrence `date`, IUCR, primary type, latitude, and longitude so
an auditor can prove every row is within the frozen window. None of those rows
or fields enters the app pack.

Inclusion is controlled by the frozen official IUCR-code mapping in
[`iucr_mapping.json`](./iucr_mapping.json), documented in
[`IUCR_MAPPING.md`](./IUCR_MAPPING.md). The pipeline separately queries all
source rows whose primary type is one of the five admitted CPD types and fails
if any such row has an IUCR outside the frozen mapping. `ASSAULT` and `BATTERY`
both map to the single `assault_battery` product category.

```sh
python3 pipeline/build_chicago_pack.py --output-dir data
python3 -m unittest discover -s pipeline/tests -v
python3 pipeline/verify_pack.py data/chicago_beta.sqlite data/chicago_beta.manifest.json
python3 pipeline/audit_disclosure.py \
  data/chicago_beta.sqlite \
  pipeline/.cache/incidents_iucr_v3_2025-07-01_2026-07-01.jsonl.gz \
  pipeline/.cache/community_areas.json.gz \
  pipeline/iucr_mapping.json
(cd data && shasum -a 256 -c chicago_beta.checksums.sha256)
```

Use `--period-end YYYY-MM-01` to pin the exclusive period end. Network responses
are cached under `pipeline/.cache/` and are not shipped. Use `--refresh` to
retrieve the same window again.

## Schema-v3 release transform

Each eligible source event is assigned exactly once to one non-overlapping 250 m
cell and exactly one category. Events with missing coordinates are excluded.
Geocoded points outside the union of the 77 official Chicago community-area
polygons are also excluded and counted in the manifest.

For every cell in the fixed official-boundary bounding rectangle—including true
zero cells—the pipeline stores only four independent nearest-five bands:

- `0` means the underlying category/cell count is 0–2;
- `5` means 3–7;
- every later multiple of five represents its nearest-five interval.

No exact cell count, total, residual, percentile, incident coordinate, source
ID, case number, date/time, block/address, description, arrest, or victim field
is shipped. Because the transform consumes only the eligible cell/category
histogram, all post-eligibility positions inside the same cell are
release-equivalent. The disclosure audit recomputes the full pack, moves every
eligible source event to two different positions inside its cell, and proves
that all singleton and two-incident category/cells release as the same zero band
as a true zero.

## Deterministic 500 m estimator

The pack estimates a scan circle from the privacy-coarsened cell bands:

1. Convert WGS84 to the documented Chicago local tangent plane anchored at
   `41.6, -87.95`, using Earth mean radius `6,371,008.8 m`.
2. Snap local x/y to the nearest whole metre, half away from zero.
3. Divide every 250 m cell into a fixed 10×10 lattice of 25 m subcells.
4. In integer decimetres, count the subcell centers whose squared distance from
   the snapped scan center is at most `5000²`.
5. A cell's area weight is `hits / 100`. Multiply each category band by hits,
   sum, divide by 100, and round the overall estimated count to the nearest
   integer half-up.
6. Compare that estimate with the identically computed distribution at the
   aligned eligible 500 m Chicago reference locations. Use the empirical
   midrank `100 × (below + 0.5 × tied) / N`, then round Cooked Score to the
   nearest five half-up.

The count is a **privacy-coarsened estimate**, not the exact number of incidents
inside the arbitrary scan circle. The result UI must say “estimated contributing
incidents.”

Reference eligibility remains conservative and explicit: every 100 m lattice
sample within the 500 m disk must be inside the official Chicago union. The same
81-point gate must run locally for an arbitrary scan; near-boundary scans fail
closed. This is a discrete coverage approximation, not a mathematical proof
that every point in the continuous disk lies inside the boundary.

The boundary label is an official Chicago community area, not a claim about an
informal neighborhood boundary. Full methodology and measured utility/privacy
tradeoffs are in [`../docs/methodology/BETA_SCORE.md`](../docs/methodology/BETA_SCORE.md).
