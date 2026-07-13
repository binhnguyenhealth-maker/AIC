# Pack-status monitor implementation

Date: 2026-07-12
Scope: operational monitoring only; no status issuance, deployment, key access,
or application changes

## Outcome

The repository now contains a read-only, daily GitHub Actions monitor for the
signed emergency pack-status object. It closes the unmonitored-expiry gap by
validating the exact object served to users and creating an actionable failure
before the signed authority expires.

## Enforcement

The monitor validates all of the following on every scheduled or manual run:

1. Canonical operations, web publish, bundled bootstrap, and production-live
   status bytes are identical.
2. The decoded signed payload is identical to the reviewed payload source.
3. The existing application trust anchor accepts at least two distinct pinned
   Ed25519 signatures and all signed schema/lifetime constraints.
4. The SHA-256 of the shipped Chicago database appears exactly once and is
   active in the signed catalog.
5. The production object is a direct, bounded HTTPS JSON response.
6. More than 24 hours of signed lifetime remain.

At 72 hours remaining, the validator emits a warning. Scheduled CI passes
`--fail-on-warning`, converting that renewal condition into a failed workflow;
at or below 24 hours it is an unconditional hard failure. Live unavailability
and integrity failures always fail closed.

## Files

- `.github/workflows/pack-status-monitor.yml` — daily/manual monitor.
- `operations/pack-status/validate_status.py` — read-only orchestration and
  expiry policy.
- `operations/pack-status/test_validate_status.py` — deterministic focused
  policy and fail-closed tests.
- `operations/pack-status/README.md` — operator behavior and renewal response.

## Residual operational responsibility

GitHub scheduling and notification delivery remain external dependencies. A
repository administrator must confirm failed-workflow notifications, assign a
named primary and backup responder, and retain evidence for each issuance and
production readback. The monitor detects and reports; it never signs, deploys,
or changes live state.

## Verification evidence

The following commands were run locally on 2026-07-12:

```sh
python3 -m py_compile \
  operations/pack-status/validate_status.py \
  operations/pack-status/test_validate_status.py
python3 -m unittest operations/pack-status/test_validate_status.py -v
python3 operations/pack-status/validate_status.py \
  --warning-hours 72 \
  --hard-fail-hours 24
git diff --check
```

Results: eight focused tests passed. The live read-only run passed exact-byte,
signature, active-pack, and lifetime validation for sequence 2, pack SHA-256
`1a18629fa3429eefec10d0d025c80102ce7c48a63457e601c1c404001686ca32`,
with signed expiry `2026-07-20T02:40:16Z`. No production state was changed.
