#!/usr/bin/env python3
"""Normalize XcodeGen's nested target attribute into OpenStep PBX syntax."""

from pathlib import Path


project = Path(__file__).resolve().parents[1] / "AIC.xcodeproj" / "project.pbxproj"
text = project.read_text(encoding="utf-8")
incorrect = 'SystemCapabilities = "[\\"com.apple.SignInWithApple.iOS\\": [\\"enabled\\": 1]]";'
correct = """SystemCapabilities = {
\t\t\t\t\t\t\tcom.apple.SignInWithApple.iOS = {
\t\t\t\t\t\t\t\tenabled = 1;
\t\t\t\t\t\t\t};
\t\t\t\t\t\t};"""

if incorrect in text:
    project.write_text(text.replace(incorrect, correct, 1), encoding="utf-8")
elif "com.apple.SignInWithApple.iOS = {" not in text:
    raise SystemExit("Sign in with Apple capability marker was not generated")
