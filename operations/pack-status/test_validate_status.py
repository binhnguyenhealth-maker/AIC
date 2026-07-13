#!/usr/bin/env python3

from __future__ import annotations

import base64
import contextlib
import datetime as dt
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


MODULE_PATH = Path(__file__).with_name("validate_status.py")
SPEC = importlib.util.spec_from_file_location("validate_status", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
monitor = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = monitor
SPEC.loader.exec_module(monitor)


class PackStatusMonitorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.paths = monitor.Paths(root)
        pack = b"test pack bytes"
        pack_sha = hashlib.sha256(pack).hexdigest()
        self.now = dt.datetime(2026, 7, 13, tzinfo=dt.timezone.utc)
        self.payload = {
            "expiresAtUnix": int((self.now + dt.timedelta(hours=96)).timestamp()),
            "issuedAtUnix": int(self.now.timestamp()),
            "packs": [{"sha256": pack_sha, "status": "active"}],
            "schemaVersion": 1,
            "sequence": 3,
        }
        self._write_tree(pack)
        self.signature_calls = 0

    def _envelope(self) -> tuple[bytes, bytes]:
        payload = json.dumps(self.payload, separators=(",", ":"), sort_keys=True).encode() + b"\n"
        envelope = json.dumps(
            {"payload": base64.b64encode(payload).decode(), "signatures": []},
            separators=(",", ":"),
            sort_keys=True,
        ).encode() + b"\n"
        return payload, envelope

    def _write_tree(self, pack: bytes) -> None:
        payload, envelope = self._envelope()
        files = {
            self.paths.pack: pack,
            self.paths.payload: payload,
            self.paths.canonical_status: envelope,
            self.paths.web_status: envelope,
            self.paths.bootstrap_status: envelope,
        }
        for path, data in files.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        self.envelope = envelope

    def _verify(self, paths: object) -> None:
        self.assertEqual(paths, self.paths)
        self.signature_calls += 1

    def _validate(self):
        return monitor.validate(
            self.paths,
            now=self.now,
            fetcher=lambda _: self.envelope,
            signature_verifier=self._verify,
        )

    def test_valid_exact_status_passes_and_invokes_signature_verifier(self) -> None:
        result = self._validate()
        self.assertEqual(result.sequence, 3)
        self.assertIsNone(result.warning)
        self.assertEqual(self.signature_calls, 1)

    def test_72_hour_window_warns(self) -> None:
        self.payload["expiresAtUnix"] = int((self.now + dt.timedelta(hours=48)).timestamp())
        self._write_tree(self.paths.pack.read_bytes())
        result = self._validate()
        self.assertIn("48.0 hours", result.warning or "")

    def test_24_hour_window_hard_fails(self) -> None:
        self.payload["expiresAtUnix"] = int((self.now + dt.timedelta(hours=24)).timestamp())
        self._write_tree(self.paths.pack.read_bytes())
        with self.assertRaisesRegex(monitor.ValidationError, "hard minimum"):
            self._validate()

    def test_live_byte_mismatch_fails_before_signature_verification(self) -> None:
        with self.assertRaisesRegex(monitor.ValidationError, "live status differs"):
            monitor.validate(
                self.paths,
                now=self.now,
                fetcher=lambda _: self.envelope + b" ",
                signature_verifier=self._verify,
            )
        self.assertEqual(self.signature_calls, 0)

    def test_checked_in_copy_mismatch_fails_closed(self) -> None:
        self.paths.web_status.write_bytes(self.envelope + b" ")
        with self.assertRaisesRegex(monitor.ValidationError, "web publish copy differs"):
            self._validate()

    def test_unsigned_payload_source_mismatch_fails_closed(self) -> None:
        self.paths.payload.write_bytes(self.paths.payload.read_bytes() + b" ")
        with self.assertRaisesRegex(monitor.ValidationError, "signed payload bytes differ"):
            self._validate()

    def test_shipped_pack_must_be_active(self) -> None:
        self.payload["packs"][0]["status"] = "withdrawn"
        self.payload["packs"][0]["reasonCode"] = "source-error"
        self._write_tree(self.paths.pack.read_bytes())
        with self.assertRaisesRegex(monitor.ValidationError, "not exactly once and active"):
            self._validate()

    def test_scheduled_warning_policy_returns_nonzero(self) -> None:
        result = monitor.ValidationResult(
            sequence=3,
            pack_sha256="a" * 64,
            expires_at_unix=int((self.now + dt.timedelta(hours=48)).timestamp()),
            remaining_seconds=48 * 60 * 60,
            warning="renew now",
        )
        with mock.patch.object(monitor, "validate", return_value=result):
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(monitor.main(["--fail-on-warning"]), 2)


if __name__ == "__main__":
    unittest.main()
