# Chicago schema-v3 release evidence

Release candidate rebuilt and audited: **2026-07-13 UTC**

The exact build-only source snapshots are retained in a private, access-limited
release-evidence archive. They are not shipped in the app or published in this
repository because the incident snapshot contains source coordinates. The
archive includes a SHA-256 checksum file, the generated manifest, and the
machine-readable disclosure-audit result.

## Integrity anchors

| Artifact | SHA-256 |
|---|---|
| Incident snapshot | `8ec77486f5f0065d5aa8535a357334be53285c7ed98c3fe9f035555295d66474` |
| Community-area snapshot | `3fd4cb3c936c0d3d61dce9b336579e19cce83f4a927703758f2cdbbb905d27b2` |
| Selected IUCR snapshot | `577eb40ee8f3a56d9f63c6a41965e581a4b3c3044bb3a95fa357b177806b8bb2` |
| Frozen IUCR mapping | `a340d5433f43489720609793b332466a8a16b2587052aafb2f34843360ae0f02` |
| Released SQLite pack | `1a18629fa3429eefec10d0d025c80102ce7c48a63457e601c1c404001686ca32` |

## Disclosure audit result

`pipeline/audit_disclosure.py` passed against the exact released SQLite pack
and the retained hash-matching snapshots:

- 138,719 eligible source events;
- 23,630 fixed-domain cells;
- at most one released cell and category influenced by each eligible event;
- 277,438 within-cell relocation trials with release-equivalent output;
- all 5,478 singleton and 3,446 two-incident category/cells released as zero;
- no positive band representing fewer than three incidents; and
- no exact or residual total released.

The audit is single-release evidence, not a differential-privacy guarantee.
The multi-release restriction in [BETA_SCORE.md](./BETA_SCORE.md) still applies.
