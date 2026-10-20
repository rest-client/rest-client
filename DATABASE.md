# DATABASE — data model and data at rest

**contractful has no database, and none is planned.** It is an HTTP client
library: it persists nothing between requests, requires no migrations, and
ships no storage engine. This document exists to make that decision explicit
and to govern the data that *does* live in the repository and in memory —
the things a database document would otherwise govern by default. If a
future feature genuinely needs persistence, it requires an ADR first
(deciding: what data, where stored, retention, and why a host application
should not own it instead).

## Data in memory at runtime

| Data | Where | Lifetime |
| --- | --- | --- |
| Request/response bodies, headers | `Request`, `Response` objects | Per call, garbage-collected with the objects |
| Cookies | `http-cookie` jar, per request or per `Resource` | Caller-owned; the library never persists jars |
| Pooled connections | `Contractful::ConnectionPool` (default global, thread-safe) | Idle connections closed at `max_idle`; keyed by host/port/proxy/SSL config including the client-cert fingerprint |
| Parsed rate-limit state | Per response object (`response.rate_limit`) | Per response |
| Contract definitions and config | Class-level `Config` objects on client classes | Process lifetime, immutable after declaration |

The connection pool is the only shared mutable state in the gem. It holds
live TCP/TLS sessions — never credentials beyond what a TLS session implies,
and its keys deliberately include the client-certificate fingerprint so
sessions authenticated as one identity can never be reused for another.

## Data at rest in the repository

The only long-lived data in this repository is **test fixtures**, all under
`spec/`:

| Fixture | Purpose | Rules |
| --- | --- | --- |
| `spec/integration/certs/isrg-root-x1.crt`, `verisign.crt` | TLS trust anchors for live SSL specs | Public root certificates only; refreshed when chains change (the 2019-era DigiCert fixture rotted and was replaced) |
| `spec/integration/capath_isrg/`, `capath_verisign/` | Hash-link `capath` directories for OpenSSL `SSLVerifyPath`-style tests | One hashed symlink/copy per root; README documents provenance |
| `spec/ISS.jpg` | Multipart upload payload | Public NASA image; no real user content |
| Inline WebMock stubs | Offline integration specs | Response bodies are synthetic; must never be recorded from authenticated endpoints |

Fixture policy:

1. **No secrets, no PII.** A fixture that contains a token, a cookie for a
   real session, or personal data is a security bug — treat it like a
   committed password (see the incident rule in
   [AGENT_TOOL_POLICY.md](security/AGENT_TOOL_POLICY.md)).
2. **Provenance documented.** Certificate fixtures say where they came from
   and when; synthetic bodies say they are synthetic.
3. **Versioned with the code.** Fixtures live in git next to the specs that
   use them; changing a fixture is a code-review-visible event, never a
   side effect of running the suite. Tests must never write fixtures.

## Logs and artifacts

The gem logs only through the caller-provided logger (`Contractful.log` /
`:log` option) and never to disk itself. Build artifacts (`pkg/`, built
`.gem` files, `rdoc/`) are disposable and must never be committed. CI
artifacts are ephemeral GitHub-hosted runner state; nothing about a CI run
persists into the repository.

## If persistence is ever needed

The gate is an ADR answering: what exact data, why the *host application*
cannot own it, where it lives (file? directory?), retention and cleanup, and
the security review (could it contain credentials or response data from
user APIs?). Absent that, "no database" remains the architecture.
