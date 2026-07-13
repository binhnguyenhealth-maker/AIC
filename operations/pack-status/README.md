# Emergency pack status

This directory contains the public, global status artifact used to stop scans
without waiting for an App Store release. Every app requests the same fixed URL:

`https://aic-beta-info.binhnguyenhealth.workers.dev/pack-status/v1/status.json`

The request has no query string or body and sends no city, coordinates, user or
device identifier, installed pack hash, or Pack Passport ID. The response is a
bounded catalog shared by every client. The app computes its bundled pack's
SHA-256 locally and matches it against that catalog.

## Trust and rollback rules

- The payload is signed by three independently stored Ed25519 keys. Clients
  require any two valid signatures.
- Clients persist the highest accepted sequence and payload digest in
  `ThisDeviceOnly` Keychain storage. Lower sequences and same-sequence conflicts
  are rejected.
- Once a given pack hash is observed as `withdrawn`, no later status may mark
  that hash active again. A corrected pack must have new bytes and a new hash.
- Signed status lifetime is at most eight days. This release uses seven days.
  HTTP caching never extends signed authority.
- Local pack freshness remains a separate, stricter gate when its cutoff occurs
  first.

This is an emergency-status MVP, not the full TUF-style pack-distribution system.
The pinned threshold keys can only be rotated in an app update. Pack downloads,
delegated city roles, transparency proofs, and atomic remote pack activation are
future work.

> **Renewal deadline:** the status committed for sequence 2 expires at
> **2026-07-20 02:40:16 UTC**. Publish a reviewed, higher-sequence issuance well
> before that time. The daily workflow alerts and fails at 72 hours remaining;
> validation hard-fails at 24 hours remaining.

## Daily expiry monitor

`.github/workflows/pack-status-monitor.yml` runs every day at 09:17 UTC and can
also be started manually. It is deliberately read-only. The monitor:

- requires the operations copy, web publish copy, bundled bootstrap, and live
  response to be byte-for-byte identical;
- requires the decoded signed payload bytes to match `status-payload.v1.json`;
- reuses `AICPackStatusValidation` to verify the pinned two-of-three Ed25519
  signatures, bounded lifetime, and shipped-pack hash/status;
- requires the live fixed URL to return direct HTTPS `application/json` within
  the response-size limit; and
- reports the sequence, pack hash, expiry, and remaining lifetime without
  reading or printing private signing material.

The policy has two gates. At 72 hours remaining the command emits a renewal
warning; the scheduled workflow uses `--fail-on-warning`, so that warning also
turns the Action red and triggers the repository's normal failed-workflow
notification path. At 24 hours remaining the validator hard-fails even without
that option. Any byte mismatch, fetch failure, invalid signature, withdrawn or
missing shipped pack, malformed object, or expired object fails immediately.

Run the same checks locally (the only network operation is a read-only GET):

```sh
python3 -m unittest operations/pack-status/test_validate_status.py -v
python3 operations/pack-status/validate_status.py \
  --warning-hours 72 \
  --hard-fail-hours 24
```

The first 72-hour alert is the issuance deadline, not an invitation to wait for
the 24-hour hard stop. The release owner should assign a primary and backup
responder in repository settings, confirm failed-workflow notifications are
enabled, issue a reviewed higher sequence, deploy the exact checked-in bytes,
and rerun the workflow. GitHub-hosted schedules are best-effort; do not treat
this monitor as a replacement for the documented manual renewal calendar.

## Key ceremony and issuance

Private keys are never stored in Git. The initial keys live under
`~/.config/aic/pack-status/` with mode `0600`; the directory is mode `0700`.
Before production use, move each key to a separate encrypted/offline custodian.
Do not keep all three on the same laptop.

Generate missing keys and print the public map:

```sh
swift operations/pack-status/PackStatusSigner.swift generate-keys \
  "$HOME/.config/aic/pack-status"
```

Review `status-payload.v1.json`, increment `sequence`, set UTC Unix timestamps,
and use either `active` with no `reasonCode`, or `withdrawn` with a short bounded
reason such as `source-error`. Sign the exact payload bytes:

```sh
swift operations/pack-status/PackStatusSigner.swift sign \
  operations/pack-status/status-payload.v1.json \
  "$HOME/.config/aic/pack-status" \
  operations/pack-status/public/v1/status.json
```

Copy the signed artifact unchanged to the fixed URL. Serve it as
`application/json`, with no cookies, redirects, personalization, or request
logging beyond short-lived operational logs. Verify the deployed bytes against
the local artifact before considering an issuance complete.

For withdrawal, publish the higher-sequence signed object first, verify it from
an unrelated network, and retain the prior object and issuance record. Never
delete or rewrite the prior issuance record; correction logging remains append-only.
