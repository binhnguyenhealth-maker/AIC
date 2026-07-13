#!/usr/bin/env python3
"""Fail when a guest-only Release app still embeds the dormant identity stack."""

from __future__ import annotations

import plistlib
import subprocess
import sys
from pathlib import Path


FORBIDDEN_FRAGMENTS = (
    "AccountAPI",
    "AccountAPIProtocol",
    "AccountEnvelope",
    "AuthSession",
    "AuthScreen",
    "DeleteAccountSheet",
    "KeychainSessionStore",
    "SessionStoring",
    "AppleNonce",
    "UsernamePolicy",
    "UsernameValidation",
    "UsernameScreen",
    "needsUsername",
    "ASAuthorizationAppleIDCredential",
    "AuthenticationServices.framework",
    "Sign in with Apple",
    "Continue without an account",
    "public @username",
    "The account service",
    "/v1/auth/apple",
    "/v1/auth/refresh",
    "/v1/usernames/",
    "/v1/account",
    "/v1/logout",
)


def binary_evidence(binary: Path) -> str:
    commands = (
        ["/usr/bin/strings", "-a", str(binary)],
        ["/usr/bin/nm", "-gjU", str(binary)],
        ["/usr/bin/otool", "-L", str(binary)],
    )
    outputs: list[str] = []
    for command in commands:
        result = subprocess.run(command, check=True, capture_output=True, text=True)
        outputs.append(result.stdout)
    return "\n".join(outputs)


def release_binaries(app: Path) -> list[Path]:
    with (app / "Info.plist").open("rb") as handle:
        executable_name = plistlib.load(handle)["CFBundleExecutable"]

    binaries = [app / executable_name]
    core = app / "Frameworks" / "AICCore.framework" / "AICCore"
    if core.exists():
        binaries.append(core)
    return binaries


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify_guest_release_binary.py /path/to/AIC.app", file=sys.stderr)
        return 2

    app = Path(sys.argv[1]).resolve()
    if not app.is_dir() or not (app / "Info.plist").is_file():
        print(f"not an application bundle: {app}", file=sys.stderr)
        return 2

    failures: list[str] = []
    for binary in release_binaries(app):
        if not binary.is_file():
            failures.append(f"missing binary: {binary}")
            continue
        contents = binary_evidence(binary)
        for fragment in FORBIDDEN_FRAGMENTS:
            if fragment in contents:
                failures.append(f"{binary.name}: found {fragment!r}")

    if failures:
        print("guest Release identity residue detected:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print(f"guest Release identity check passed for {app}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
