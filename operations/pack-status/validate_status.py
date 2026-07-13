#!/usr/bin/env python3
"""Read-only operational validation for AIC's signed pack-status artifact."""

from __future__ import annotations

import argparse
import base64
import dataclasses
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Callable
import urllib.request


LIVE_STATUS_URL = (
    "https://aic-beta-info.binhnguyenhealth.workers.dev/"
    "pack-status/v1/status.json"
)
MAX_STATUS_BYTES = 64 * 1024


class ValidationError(RuntimeError):
    """The public status is not safe to rely on."""


@dataclasses.dataclass(frozen=True)
class Paths:
    repo_root: Path

    @property
    def pack(self) -> Path:
        return self.repo_root / "data/chicago_beta.sqlite"

    @property
    def payload(self) -> Path:
        return self.repo_root / "operations/pack-status/status-payload.v1.json"

    @property
    def canonical_status(self) -> Path:
        return self.repo_root / "operations/pack-status/public/v1/status.json"

    @property
    def web_status(self) -> Path:
        return self.repo_root / "web/public/pack-status/v1/status.json"

    @property
    def bootstrap_status(self) -> Path:
        return self.repo_root / "ios/AIC/Resources/pack_status_bootstrap.json"


@dataclasses.dataclass(frozen=True)
class ValidationResult:
    sequence: int
    pack_sha256: str
    expires_at_unix: int
    remaining_seconds: float
    warning: str | None


FetchStatus = Callable[[str], bytes]
RunSignatureVerifier = Callable[[Paths], None]


def _read_bounded(path: Path, maximum: int = MAX_STATUS_BYTES) -> bytes:
    try:
        size = path.stat().st_size
        if size > maximum:
            raise ValidationError(f"{path} exceeds the {maximum}-byte limit")
        return path.read_bytes()
    except OSError as error:
        raise ValidationError(f"cannot read {path}: {error}") from error


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fetch_live_status(url: str) -> bytes:
    if not url.startswith("https://"):
        raise ValidationError("live status URL must use HTTPS")
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": "AIC-Pack-Status-Monitor/1",
        },
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            if response.status != 200:
                raise ValidationError(f"live status returned HTTP {response.status}")
            if response.geturl() != url:
                raise ValidationError("live status redirected away from the fixed URL")
            content_type = response.headers.get_content_type()
            if content_type != "application/json":
                raise ValidationError(
                    f"live status content type is {content_type}, expected application/json"
                )
            body = response.read(MAX_STATUS_BYTES + 1)
    except ValidationError:
        raise
    except Exception as error:
        raise ValidationError(f"live status fetch failed: {error}") from error
    if len(body) > MAX_STATUS_BYTES:
        raise ValidationError(f"live status exceeds the {MAX_STATUS_BYTES}-byte limit")
    return body


def run_signature_verifier(paths: Paths) -> None:
    command = [
        "swift",
        "run",
        "--package-path",
        str(paths.repo_root / "ios"),
        "AICPackStatusValidation",
        str(paths.pack),
        str(paths.bootstrap_status),
        str(paths.canonical_status),
    ]
    try:
        completed = subprocess.run(
            command,
            cwd=paths.repo_root,
            check=False,
            capture_output=True,
            text=True,
            timeout=300,
        )
    except subprocess.TimeoutExpired as error:
        raise ValidationError("threshold signature verification timed out") from error
    except OSError as error:
        raise ValidationError(f"cannot start threshold signature verifier: {error}") from error
    if completed.returncode != 0:
        diagnostic = (completed.stderr or completed.stdout).strip()
        diagnostic = diagnostic[-2_000:] if diagnostic else "no diagnostic output"
        raise ValidationError(f"threshold signature verification failed: {diagnostic}")


def _decode_payload(envelope_data: bytes) -> tuple[bytes, dict[str, object]]:
    try:
        envelope = json.loads(envelope_data)
        if not isinstance(envelope, dict):
            raise TypeError("envelope is not an object")
        encoded_payload = envelope["payload"]
        if not isinstance(encoded_payload, str):
            raise TypeError("payload is not a string")
        payload_data = base64.b64decode(encoded_payload, validate=True)
        payload = json.loads(payload_data)
        if not isinstance(payload, dict):
            raise TypeError("payload is not an object")
        return payload_data, payload
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        raise ValidationError(f"cannot decode signed status payload: {error}") from error


def validate(
    paths: Paths,
    *,
    live_url: str = LIVE_STATUS_URL,
    warning_hours: float = 72,
    hard_fail_hours: float = 24,
    now: dt.datetime | None = None,
    fetcher: FetchStatus = fetch_live_status,
    signature_verifier: RunSignatureVerifier = run_signature_verifier,
) -> ValidationResult:
    if warning_hours <= hard_fail_hours or hard_fail_hours < 0:
        raise ValidationError("warning hours must be greater than nonnegative hard-fail hours")

    canonical = _read_bounded(paths.canonical_status)
    for label, path in (
        ("web publish copy", paths.web_status),
        ("bundled bootstrap", paths.bootstrap_status),
    ):
        candidate = _read_bounded(path)
        if candidate != canonical:
            raise ValidationError(
                f"{label} differs from canonical status "
                f"(canonical {_sha256(canonical)}, candidate {_sha256(candidate)})"
            )

    live = fetcher(live_url)
    if live != canonical:
        raise ValidationError(
            "live status differs from checked-in canonical bytes "
            f"(canonical {_sha256(canonical)}, live {_sha256(live)})"
        )

    payload_data, payload = _decode_payload(canonical)
    source_payload = _read_bounded(paths.payload, maximum=32 * 1024)
    if source_payload != payload_data:
        raise ValidationError(
            "signed payload bytes differ from status-payload.v1.json "
            f"(signed {_sha256(payload_data)}, source {_sha256(source_payload)})"
        )

    signature_verifier(paths)

    try:
        sequence = payload["sequence"]
        expires_at_unix = payload["expiresAtUnix"]
        packs = payload["packs"]
        if not isinstance(sequence, int) or isinstance(sequence, bool) or sequence <= 0:
            raise TypeError("sequence is not a positive integer")
        if (
            not isinstance(expires_at_unix, int)
            or isinstance(expires_at_unix, bool)
            or expires_at_unix <= 0
        ):
            raise TypeError("expiresAtUnix is not a positive integer")
        if not isinstance(packs, list):
            raise TypeError("packs is not an array")
    except (KeyError, TypeError) as error:
        raise ValidationError(f"signed payload shape is invalid: {error}") from error

    try:
        pack_sha256 = _sha256(paths.pack.read_bytes())
    except OSError as error:
        raise ValidationError(f"cannot hash {paths.pack}: {error}") from error
    matching_entries = [
        entry
        for entry in packs
        if isinstance(entry, dict) and entry.get("sha256") == pack_sha256
    ]
    if len(matching_entries) != 1 or matching_entries[0].get("status") != "active":
        raise ValidationError("shipped pack hash is not exactly once and active in signed status")

    current = now or dt.datetime.now(dt.timezone.utc)
    if current.tzinfo is None:
        raise ValidationError("current time must include a timezone")
    remaining_seconds = expires_at_unix - current.timestamp()
    hard_fail_seconds = hard_fail_hours * 60 * 60
    warning_seconds = warning_hours * 60 * 60
    if remaining_seconds <= hard_fail_seconds:
        raise ValidationError(
            f"signed status has {remaining_seconds / 3600:.1f} hours remaining; "
            f"hard minimum is more than {hard_fail_hours:.1f} hours"
        )
    warning = None
    if remaining_seconds <= warning_seconds:
        warning = (
            f"signed status has only {remaining_seconds / 3600:.1f} hours remaining; "
            "publish and verify a reviewed higher sequence now"
        )

    return ValidationResult(
        sequence=sequence,
        pack_sha256=pack_sha256,
        expires_at_unix=expires_at_unix,
        remaining_seconds=remaining_seconds,
        warning=warning,
    )


def _github_annotation(level: str, title: str, message: str) -> str:
    safe = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    return f"::{level} title={title}::{safe}"


def _write_summary(result: ValidationResult) -> None:
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return
    expires = dt.datetime.fromtimestamp(result.expires_at_unix, dt.timezone.utc)
    lines = [
        "## Pack-status monitor\n",
        f"- Sequence: `{result.sequence}`\n",
        f"- Pack SHA-256: `{result.pack_sha256}`\n",
        f"- Expires: `{expires.isoformat().replace('+00:00', 'Z')}`\n",
        f"- Remaining: `{result.remaining_seconds / 3600:.1f} hours`\n",
    ]
    with open(summary_path, "a", encoding="utf-8") as summary:
        summary.writelines(lines)


def parse_args(argv: list[str]) -> argparse.Namespace:
    default_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=default_root)
    parser.add_argument("--live-url", default=LIVE_STATUS_URL)
    parser.add_argument("--warning-hours", type=float, default=72)
    parser.add_argument("--hard-fail-hours", type=float, default=24)
    parser.add_argument(
        "--fail-on-warning",
        action="store_true",
        help="exit 2 in the renewal window so scheduled CI creates an alert",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    try:
        result = validate(
            Paths(args.repo_root.resolve()),
            live_url=args.live_url,
            warning_hours=args.warning_hours,
            hard_fail_hours=args.hard_fail_hours,
        )
    except ValidationError as error:
        if os.environ.get("GITHUB_ACTIONS") == "true":
            print(_github_annotation("error", "Pack status invalid", str(error)), file=sys.stderr)
        print(f"PACK_STATUS_MONITOR_ERROR: {error}", file=sys.stderr)
        return 1

    expires = dt.datetime.fromtimestamp(result.expires_at_unix, dt.timezone.utc)
    print("PACK_STATUS_MONITOR_OK")
    print(f"sequence={result.sequence}")
    print(f"pack_sha256={result.pack_sha256}")
    print(f"expires_at={expires.isoformat().replace('+00:00', 'Z')}")
    print(f"remaining_hours={result.remaining_seconds / 3600:.1f}")
    _write_summary(result)
    if result.warning:
        if os.environ.get("GITHUB_ACTIONS") == "true":
            print(_github_annotation("warning", "Pack status renewal due", result.warning))
        print(f"PACK_STATUS_MONITOR_WARNING: {result.warning}", file=sys.stderr)
        return 2 if args.fail_on_warning else 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
