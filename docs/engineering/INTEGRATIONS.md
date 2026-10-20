# INTEGRATIONS — dependencies, platforms and external touchpoints

contractful sits in the middle of an integration web: it wraps Net::HTTP,
depends on four small runtime libraries, supports a Windows platform gem,
is exercised in CI by GitHub Actions and httpbin.org, and is consumed by
downstream SDK projects. This document records each integration, why it
exists, its constraints, and the policy for changing it.

## Runtime dependencies (the allowed surface)

| Dependency | Version | Why it exists | Constraint |
| --- | --- | --- | --- |
| `http-accept` | >= 1.7.0, < 2.0 | Parsing `Accept`-header logic for negotiation | none known |
| `http-cookie` | >= 1.0.2, < 2.0 | RFC 6265 cookie jar: parsing Set-Cookie, replaying cookies, redirect-safe jar handling | header/value canonicalization quirks are its domain, not ours |
| `mime-types` | >= 1.16, < 4.0 | Content-type detection for payloads and multipart parts | large data table; do not widen use |
| `netrc` | ~> 0.8 | `~/.netrc` credential lookup for hosts | credentials stay out of code |

Policy: adding anything here requires an ADR (quality gate G5). The
contract-first layer deliberately added **zero** runtime dependencies —
that is a design constraint, not an accident. Validation engines
(JSON-Schema, dry-schema), OpenAPI parsers and the like must stay
opt-in tools outside the require path, if they ever ship.

## Standard library integration: Net::HTTP + OpenSSL

Net::HTTP is the only transport (ADR-listed in ARCHITECTURE.md). The gem
types its options against what Net::HTTP actually supports, which produced
two adaptation layers worth knowing before touching request.rb:

- **`normalize_ssl_version`** — maps `:TLSv1_2`-style symbols,
  `:TLS1_2`-style symbols and strings onto the OpenSSL integer constants,
  because Ruby 4.0's OpenSSL rejects the old symbol spellings. Never pass
  raw version symbols to `Net::HTTP` from new code paths.
- **Timeout plumbing** — `:open_timeout`, `:read_timeout`, `:write_timeout`
  (and total `:timeout`) map onto the corresponding Net::HTTP attributes;
  `Net::WriteTimeout` exists only on sufficiently modern Rubies, which the
  `>= 3.0` requirement guarantees.

## Platform integration: Windows

`contractful.windows.gemspec` publishes a platform gem for
`x64-mingw-ucrt` with `ffi ~> 1.16`, loading the Windows certificate store
(`lib/contractful/windows/root_certs.rb`) so TLS verification works without
a CA bundle file. The main gemspec's file list excludes this code; the
Rakefile's `windows:*` tasks build/push per-platform gems. When touching
SSL defaults, remember the two platforms get trust from different stores —
specs cover the Windows loader separately
(`spec/unit/windows/root_certs_spec.rb`).

## Development-time integrations

| Tool | Role | Notes |
| --- | --- | --- |
| RSpec + WebMock | offline HTTP behavior | see TESTING.md conventions and traps |
| httpbin.org | live end-to-end target (TLS, redirects, headers, forms) | CI reaches it deliberately; `HTTPBIN_URL` overrides for proxied environments |
| GitHub Actions | CI matrix 3.0–4.0 + experimental head | `permissions: contents: read` |
| mise | reference Ruby toolchain (4.0.7) | see SETUP.md |
| RubyGems | distribution | publication is maintainer-only (`gem push` gated by AGENT_TOOL_POLICY.md) |

## Extension points for host applications

- **Callbacks:** `before_request` (mutable context — inject tracing
  headers, auth, request IDs) and `after_response` (observe validated
  responses — metrics, logging) accumulate down client-class hierarchies.
- **Logging:** `Contractful.log=` / `CONTRACTFUL_LOG` route the gem's own
  log lines into the host's logging stack.
- **Connection pooling:** `persistent: true` per request or per
  `Resource`; the pool is inspectable (`Contractful.connection_pool`).
- **Contract introspection:** `contracts`, `contract_for`,
  `Definition#describe` — build documentation, dashboards or MCP tool
  schemas from declarations instead of scraping methods.

## Downstream consumers

The motivating downstream project is a **DhanHQ trading client**. Findings
from the 2026-10 investigation, worth keeping because they shape both this
gem's roadmap and the client's design: DhanHQ publishes **no
machine-readable API specification** — the docs are prose, the dhan-oss
organization hosts client libraries for other languages, and community
Postman collections are not authoritative. Consequently a `dhanhq-client`
built on this gem must **author its contract from the documentation**: the
dual-header auth (`access-token` + `client-id`) maps to
`auth api_key: [...]`, the prose rate limits yield `response.rate_limit ==
nil` until real headers appear (data absence, not an error), and the
vendor's error-code annexure maps onto the retryable/terminal
classification. That consumer lens is what prioritized idempotency keys,
pagination and rate-limit work in this release.

## Telemetry policy

None. The gem makes no network calls except those the caller requests, no
phones-home, no usage statistics, no version pings. Every host a request
reaches is one the caller named. This is a permanent policy: any PR that
introduces an outbound call not explicitly requested by the caller is
rejected regardless of purpose.
