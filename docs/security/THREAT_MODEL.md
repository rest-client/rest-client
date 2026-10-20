# THREAT MODEL — assets, boundaries, mitigations

Scope: the contractful gem itself — the code users load into their
applications. contractful has no server, no state store and no privileges
beyond its host process; its threat model is therefore about **being a
correct, safe conduit between a trusting application and a hostile
network**, plus the supply chain that delivers it. This model follows the
OWASP application-security structure (architecture, threat identification,
verification) at the scale appropriate for a client library. Security
issues are reported privately — see CONTRIBUTING.md.

## Assets (what must be protected)

| Asset | Description |
| --- | --- |
| A1 | Caller credentials in flight: basic-auth, `Authorization` headers, netrc entries, client certificates, contract-resolved API keys |
| A2 | Caller request integrity: payloads and params must reach the intended host unmodified and unobserved |
| A3 | Response integrity: what the library returns must be what the server sent — no silent reinterpretation that changes meaning |
| A4 | Host process safety: no code execution from response content, no path/graph traversal via responses |
| A5 | TLS posture: verification defaults cannot be silently weakened |
| A6 | Supply chain: gems, dependencies, CI — the path from source to user |
| A7 | CI credentials: tokens used by agents and maintainers |

## Trust boundaries

```text
[ caller application ] ──(trusted)──► [ contractful ] ──(UNTRUSTED)──► [ network/server ]
                                             ▲
                              (semi-trusted) │
                              env vars, netrc, CA files, gem source
```

The caller is trusted (it hands us its credentials and its URLs). Everything
beyond process memory is untrusted: servers lie, mangle, redirect and
overshare; local files (netrc, CA bundles) are semi-trusted inputs; gem
sources and CI are supply-chain boundaries.

## Threats and mitigations

| ID | Threat | Mitigation | Status |
| --- | --- | --- | --- |
| T1 | MITM downgrade/interception of TLS sessions | Certificate verification on by default; `ssl_min_version`/`ssl_max_version` normalized through `normalize_ssl_version` so floors are actually applied on Ruby 4.0 OpenSSL; TLS fixtures (ISRG Root X1) verify real chains in CI | mitigated |
| T2 | Hostile server manipulates control data: malicious `Location` (redirect loops, cross-host hops), poisoned `Set-Cookie`, oversized/malformed headers | Redirect cap (`:max_redirects`, default 10); cookie handling delegated to `http-cookie` (RFC 6265 parsing); Net::HTTP rejects malformed header values | mitigated; cross-host cookie-forwarding rules inherited from http-cookie — documented behavior, not changed here |
| T3 | Resource exhaustion: huge bodies, slow responses (slowloris-style) stalling host apps | Phase timeouts (`open/read/write/total`) exposed and defaulted sanely; retries bounded by `:max_retries`; pagination bounded by `_max_pages` | mitigated; no default body-size cap — **residual risk**, callers streaming untrusted content should use `raw_response` and their own limits |
| T4 | SSRF by configuration: caller points the client at internal metadata endpoints | Out of scope by design — the caller owns URL choice; the library refuses no destinations. Documented responsibility; contract layer narrows exposure by fixing `base` per client class | accepted (documented) |
| T5 | Credential leakage through errors and logs: tokens in exception messages, logs, or `inspect` output | Exception messages carry status/class, not bodies or auth headers; logging goes only to caller-provided loggers, with README guidance to avoid logging auth/cookie headers; netrc/credentials never rendered | mitigated; callers still own their log content |
| T6 | Response-content code execution (`eval` of server data, YAML deserialization of responses) | The library never `eval`s, never YAML-loads, never constantizes response content; `Response#json` is `JSON.parse` only; contract layer validates shapes rather than instantiating classes from data | mitigated (by absence, enforced in review via gate G12) |
| T7 | Dependency/supply-chain compromise (malicious or compromised gem releases, dependency confusion) | Small pinned dependency ranges (`http-accept`, `http-cookie`, `mime-types`, `netrc`); zero new runtime deps without ADR; gem built from `git ls-files`; `rubygems_mfa_required` metadata; publication is maintainer-only with MFA | mitigated; no lockfile-based CI pinning — **residual risk** typical of library gems |
| T8 | Secret leakage through the development workflow (tokens in remote URLs, fixtures, CI logs) | AGENT_TOOL_POLICY.md: tokenless remotes required, credential-helper preference, no secrets in fixtures (DATABASE.md policy), CI `permissions: contents: read` | mitigated by policy; **agents must audit their own diffs (gate G10)** |
| T9 | Contract-layer semantics weaken safety: silent coercion hiding bad input, unknown params accepted by default | Strict-mode default (`UnknownParam`); constraints enforced post-coercion pre-network; response values never coerced; contract violations raise precisely | mitigated; `strict_params false` / resource-macro looseness is explicit opt-in |

## Explicit non-goals

- Policing caller URL choices (T4) or response bodies' content (beyond
  never executing them).
- Defending against a compromised host process — once the attacker runs in
  process, all bets are off for any library.
- hardening Net::HTTP itself; upstream behavior is inherited and documented.

## Verification

Security-relevant behavior is spec-covered, not aspirational: SSL
normalization and CA loading (request specs + live TLS specs against real
chains), timeout plumbing, retry classification (error_classification_spec),
pool keying including certificate fingerprints (connection_pool_spec),
closed-schema rejection order (contract/param_spec, executor_spec). The
release checklist (DELIVERY.md) re-runs the live TLS specs so chain rot —
the 2019 DigiCert fixture incident — is caught before users do.

## Reporting

Private channels only (see CONTRIBUTING.md): contact the repository owner.
Include reproduction, affected versions, and impact assessment. Fixes ship
on the normal cadence once a patch exists; DoS-class issues with public
workarounds may be disclosed in README notes.
