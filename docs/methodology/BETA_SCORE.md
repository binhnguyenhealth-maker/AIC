# Cooked Score Beta — Chicago schema-v3 method

Status: **provisional descriptive beta**

Methodology version: `beta-cell250-q5-area-v3`

Consumer name: **Cooked Score Beta**

Methodology name: **Reported Incident Exposure Index**

## Required interpretation

> Cooked Score Beta compares historical reported-incident concentration around
> this location with eligible Chicago comparison locations. It is not a live
> safety assessment or personal-risk prediction.

The v3 score is a Chicago-only percentile of a privacy-coarsened estimate. It is
not an exact incident count, a forecast, a probability of victimization, a live
danger signal, a causal statement about a neighborhood, or a score comparable
with any other city.

## Source window and categories

- Crime source: City of Chicago `ijzp-q8t2`.
- IUCR source: Chicago Police Department `c7ck-438e`.
- Boundary source: City of Chicago `igwz-8jzy`.
- Frozen window: `2025-07-01 <= occurrence date < 2026-07-01`.
- Source-through date: `2026-06-30`.
- Selected geocoded rows: 139,082.
- Geocoded rows outside the union of official community areas, excluded before
  aggregation: 433.
- Eligible source rows aggregated: 138,649.
- Selected rows missing coordinates, excluded: 49.
- Selected-primary rows outside the frozen IUCR mapping: 0; any nonzero result
  fails the build.

The four mutually exclusive product categories are:

1. assault and battery;
2. robbery;
3. theft;
4. motor-vehicle theft.

The frozen taxonomy and fail-closed rules are indexed in
[`IUCR_MAPPING.md`](./IUCR_MAPPING.md).

Every eligible incident contributes one count to exactly one category and one
non-overlapping cell. There are no severity weights, recency weights,
time-of-day adjustments, demographic inputs, smoothing, predictions, or
cross-city comparisons.

## Privacy-coarsened release

The build uses a public local tangent grid anchored at latitude `41.6`, longitude
`-87.95`, with Earth mean radius `6,371,008.8 m`. Each incident maps by `floor`
to one 250 m square cell.

For each category independently:

```text
band(n) = 5 × floor(n / 5 + 0.5)
```

Thus a released zero represents a true count from 0 through 2, and a released
five represents 3 through 7. The pack includes all 23,630 cells in the fixed
official-boundary bounding rectangle, including cells whose four bands are all
zero. Absence cannot signal that a cell had no source events.

The pack never releases an exact cell total, a residual total, an incident row,
an incident coordinate, an IUCR code, a source ID, a date/time, an address or
block, an arrest flag, a description, or victim information. The four bands are
the only incident-derived values in `aggregate_cells`.

Eligibility is evaluated before aggregation. After a source row is eligible,
its within-cell position is not used by the release transform. Moving it to any
other position that remains in the same cell/category produces the same pack.

## Deterministic area-weighted 500 m estimate

The iOS consumer and Python pipeline must implement the following algorithm
exactly.

### Coordinate conversion

```text
x = radians(longitude - (-87.95)) × 6,371,008.8 × cos(radians(41.6))
y = radians(latitude - 41.6) × 6,371,008.8
```

Snap `x` and `y` independently to the nearest whole metre, with half values away
from zero. Convert to integer decimetres.

Constants in decimetres:

```text
cell side                 = 2500
radius                    = 5000
radius squared inclusive  = 25,000,000
subcell side              = 250
first subcell-center offset = 125
```

### Cell weight

Divide each candidate cell into 10 rows × 10 columns. Its 100 deterministic
subcell centers are:

```text
sample_x = cell_column × 2500 + 125 + subcell_column × 250
sample_y = cell_row    × 2500 + 125 + subcell_row    × 250
```

A sample is inside when:

```text
(sample_x - center_x)^2 + (sample_y - center_y)^2 <= 25,000,000
```

Let `hits(cell)` be the number inside. The estimated category numerator is:

```text
category_numerator = Σ cell_category_band × hits(cell)
category_estimate  = category_numerator / 100
```

The estimated contributing count used for percentile lookup is the half-up
integer:

```text
estimated_total = floor((Σ category_numerator + 50) / 100)
```

Displayed category estimates use balanced largest-remainder rounding so they
sum to the same displayed estimated total.

## Eligible Chicago reference distribution

Candidate reference centers lie on the same public local grid at nominal 500 m
spacing. A center is eligible only when each of the 81 aligned 100 m lattice
samples within its inclusive 500 m disk lies inside the union of the 77 official
community-area polygons. There are 2,003 eligible references in this pack.

This gate is deliberately conservative but discrete. It does not prove that
every point in the continuous disk is inside Chicago. The app applies the same
gate locally and suppresses near-boundary scans that fail it.

V3 has no count-based minimum because its released bands already coarsen low
cells; a numeric score requires valid schema/source metadata, the nonempty
2,003-reference distribution, and a passing 81-point coverage gate, and is
otherwise suppressed rather than treating missing data as zero.

Compute `estimated_total` for every eligible reference using the same v3 cell
bands and area estimator. For a scan estimate `c`, with `N` references:

```text
percentile(c) = 100 × (references below c + 0.5 × references tied at c) / N
Cooked Score  = nearest-five-half-up(percentile), clamped to 0...100
```

## Measured utility

The build compared v3 estimates against exact 500 m counts at all 50,049
eligible 100 m evaluation nodes. Exact source points and node counts existed
only in build memory and were not shipped.

| Metric | Result |
|---|---:|
| Cooked Score exactly matched the exact-count baseline | 51.58% |
| Cooked Score within 5 points | 92.06% |
| Cooked Score within 10 points | 97.97% |
| Cooked Score absolute error, p95 | 10 points |
| Estimated-count absolute error, median | 13 incidents |
| Estimated-count absolute error, p95 | 54 incidents |
| Dominant category agreement | 91.54% |

The deterministic cardinal-movement check sampled 2,000 pairs at each distance:

| Movement | Median score change | p95 | Maximum | Fraction over 10 |
|---|---:|---:|---:|---:|
| 10 m | 0 | 5 | 5 | 0% |
| 25 m | 0 | 5 | 5 | 0% |
| 50 m | 0 | 5 | 15 | 0.05% |

These results support a descriptive beta score, not an exact incident-count
claim. Hotspot outliers can have much larger count error; the UI must use
“estimated contributing incidents.”

## Disclosure verification

The default standard-library disclosure audit independently rebuilds the cell
bands from the ignored source snapshot and verifies:

- one eligible event influences at most one cell and one category;
- 277,298 post-eligibility within-cell relocation trials preserve the released
  cell;
- all 5,480 singleton category/cells release as zero;
- all 3,442 two-incident category/cells release as zero;
- every positive band has an underlying count of at least three;
- no exact/residual total or subcell coordinate is present;
- the shipped 23,630-row band table exactly matches independent recomputation.

This is a practical single-release protection, not a formal differential-privacy
guarantee. Deterministic differencing across future monthly packs could leak
threshold crossings. Do not publish a second rolling-window v3 pack without a
new multi-release disclosure review or an approved privacy-budgeted mechanism.

## Source and coverage limitations

Chicago Police Department data reflects reported incidents, is preliminary,
may be revised, may contain errors or omissions, and does not capture unreported
incidents. Source-map locations are approximate. Reporting and enforcement
patterns are not uniform. Official community areas are stable administrative
labels, not exact informal-neighborhood boundaries.

The pack is Chicago-specific. Water, boundary, missing-coordinate, unknown-IUCR,
and outside-official-boundary handling are recorded in the manifest. No score
should be shown when coverage or schema validation fails.
