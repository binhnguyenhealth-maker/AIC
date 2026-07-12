# Security Policy

## Supported scope

This repository is an engineering beta. Security reports are welcome for the
iOS client, account Worker, data-pack pipeline, bundled release data, and
public web pages on the current `main` branch.

Important security and privacy invariants include:

- Scan coordinates, pins, routes, addresses, and history remain on device.
- Authentication and deletion operations remain bound to the correct Apple
  subject and AIC account.
- Credentials and deployment secrets never enter source control or logs.
- External data is validated and bounded before affecting release artifacts.
- The shipped data pack contains no source incident coordinates, identifiers,
  addresses, timestamps, or exact sparse counts.

## Reporting a vulnerability

Please do not publish suspected vulnerabilities in a public issue. Use
GitHub's private vulnerability reporting feature for this repository. Include:

- the affected revision and file;
- prerequisites and a minimal reproduction;
- the expected and observed security boundary;
- impact and any suggested remediation.

Do not test against live accounts, Apple identities, or deployed services that
you do not own or have explicit authorization to test.

## Non-security reports

Incorrect scores, data-quality concerns, user-interface bugs, and feature
requests should use ordinary GitHub issues when issue tracking is enabled.
