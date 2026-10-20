# Security Policy

Contractful is an HTTP client: it holds credentials, talks to remote APIs
and parses their responses. This document explains what is in scope, how to
report a vulnerability and what to expect.

## Supported versions

| Version | Supported |
| --- | --- |
| 0.1.x | yes |

Only the latest published 0.x line receives security fixes. Pre-release
commits on `master` are not a supported channel — pin a released version.

## Reporting a vulnerability

**Do not open a public issue for a security report.**

Use GitHub's private vulnerability reporting for this repository
(**Security → Report a vulnerability**), which reaches the maintainers
directly and keeps the report confidential until a fix is shipped. If you
cannot use the GitHub channel, open a plain issue asking for a private
contact channel — never include the details in the issue itself.

Please include what you can of: affected version(s) and Ruby version, a
minimal reproduction (script, contract definition or raw request), the
impact you believe is possible, and whether the issue is known to be
exploited. Reports are acknowledged within 7 days; if you do not hear back
in that window, assume the report did not arrive and follow up publicly
without details.

## Scope

In scope:

- Credential handling — anything that leaks `auth` values, headers or
  payloads into logs, exceptions, `inspect` output or the recorded-sequence
  fixtures beyond the documented redaction rules
- TLS verification — ways to disable or downgrade certificate verification
  that the documented API does not sanction
- Redirect behavior — credential or header leakage across hosts on a
  redirect chain
- Parameter/contract validation — a way to bypass the closed-request schema
  and send undeclared params to the wire
- Dependency-level issues in the runtime dependency set (`http-cookie`,
  `http-accept`, `mime-types`, `netrc`)

Out of scope: denial-of-service by requesting huge resources (size is the
caller's choice), issues in test-only helpers (`openapi_import`, `sequence`)
when used outside development, and social engineering of API vendors.

## Design references

The security-relevant invariants this gem commits to are written down in
[docs/security/THREAT_MODEL.md](docs/security/THREAT_MODEL.md) (asset-by-
threat analysis, including log redaction and the credential-movement rules
CI enforces) and [docs/engineering/ERROR_HANDLING.md](docs/engineering/ERROR_HANDLING.md)
(fail-loudly policy). Fixes are expected to keep those documents true.

## Disclosure policy

Fixes land on `master` first and ship in the next release; the advisory is
published via GitHub Security Advisories with credit to the reporter unless
the reporter prefers anonymity. Details are disclosed after a fixed version
is available on RubyGems — for 0.x releases that means the fix version, not
a backport, since only one line is supported.
