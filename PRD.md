# PRD — Product Requirements Document

contractful is a simple HTTP and REST client for Ruby, inspired by the
Sinatra microframework style of specifying actions (`get`, `post`, `put`,
`delete`). The upstream gem was archived in 2019; this fork keeps it alive
and carries it forward with two product goals: run flawlessly on modern Ruby
(3.0–4.0 and beyond), and give API SDK authors a **contract-first layer**
(`Contractful::Contract`) that turns interface declarations into generated,
validated client code.

## Goals

1. **Reliable simplicity.** The one-liner `Contractful.get(url)` must keep
   working exactly as users expect, with sane defaults and precise
   exceptions when things go wrong.
2. **Modern Ruby, verified.** Every commit is tested on Ruby 3.0, 3.1, 3.2,
   3.3, 3.4 and 4.0 in CI, with an experimental `ruby-head` job. Compatibility
   bugs are found by the matrix, not by users.
3. **Contract-first API clients.** Developers declaring an API client should
   write *what* the API looks like (verbs, paths, typed params, expected
   responses) and let the gem generate the client methods, validation,
   pagination and introspection. The contract is the implementation; there is
   no imperative request code to drift out of sync.
4. **Small, deliberate dependency surface.** Four runtime dependencies
   (`http-accept`, `http-cookie`, `mime-types`, `netrc`), zero added by the
   contract layer.

## Non-goals

- Asynchronous or concurrent request execution (no eventmachine/async_http).
- Browser emulation beyond cookies, redirects and headers.
- Server-side request validation — the contract layer validates *this* gem's
  outgoing requests and incoming responses, not other parties' servers.
- Replacing general-purpose HTTP tooling (faraday-style middleware stacks).

## Target users

- **Application developers** who need a dependable, low-ceremony HTTP client
  and clear exceptions instead of silent failures.
- **API SDK authors** who wrap a vendor API (a trading platform, a SaaS
  product) and want typed, validated, documented client methods generated
  from declarations.
- **Maintainers of long-lived Ruby apps** stuck on old rest-client 1.x/2.x
  who need a drop-in that works on modern Rubies.

## Feature requirements

IDs are normative; the traceability matrix in
[docs/requirements/REQUIREMENTS.md](docs/requirements/REQUIREMENTS.md) maps
each to acceptance criteria and specs. The "Upstream since" column records
the rest-client release line in which the feature first appeared;
contractful ships all of them from 0.1.0.

| ID | Feature | Upstream since |
| --- | --- | --- |
| FR-1 | One-liner DSL: `Contractful.get/post/put/patch/delete/head/options` | 1.x |
| FR-2 | `Resource` / ActiveResource-style nesting | 1.x |
| FR-3 | Payloads: form-encoded, JSON, raw, multipart file upload, streaming | 1.x |
| FR-4 | Headers, params (`ParamsArray` for repeated keys), cookies | 1.x |
| FR-5 | Timeouts: `timeout`, `open_timeout`, `read_timeout`, `write_timeout` | 1.x / 2.2 |
| FR-6 | SSL/TLS control: CA file, client certs, `ssl_min_version`/`ssl_max_version` | 1.x / 2.2 |
| FR-7 | Redirect following (GET/HEAD by default; opt-in for others) | 1.x |
| FR-8 | Exception-per-status error model with the response attached | 1.x |
| FR-9 | Logging hook (`Contractful.log`, `CONTRACTFUL_LOG`) | 1.x |
| FR-10 | Proxy support (ENV-based and per-request) | 1.x |
| FR-11 | Automatic retries with exponential backoff, honoring `Retry-After` | 2.3 |
| FR-12 | Persistent connections via a thread-safe connection pool | 2.3 |
| FR-13 | `Response#json` convenience parsing | 2.3 |
| FR-14 | Contract DSL: typed, validated, closed-schema params | 2.4 |
| FR-15 | Response contracts: `responds` statuses/types, `response_field` open schemas | 2.4 / 2.5 |
| FR-16 | Auth in the contract: `bearer:`, `api_key:`, `basic:`, callable credentials | 2.5 |
| FR-17 | Idempotency keys, stable across automatic retries | 2.5 |
| FR-18 | Pagination contracts with metaprogrammed page enumerators | 2.5 |
| FR-19 | Rate-limit header parsing (`RateLimit-*`, `X-RateLimit-*`) | 2.5 |
| FR-20 | Retryable vs terminal error classification | 2.5 |
| FR-21 | `before_request` / `after_response` callbacks with inheritance | 2.4 |
| FR-22 | CRUD `resource` macro, reflection and dynamic dispatch | 2.4 |
| FR-23 | Windows support gem (`x64-mingw-ucrt`) | 1.x |
| FR-24 | Ruby 3.0–4.0 compatibility, CI-enforced | 2.2 |

## Success metrics

- CI matrix green on every push (hard gate; a red matrix blocks merge).
- Zero open bug reports about Ruby 3.x/4.x incompatibility after a release.
- The public API stays drop-in compatible for rest-client 2.x users; breaking
  changes require a major version and a documented migration path.
- Contract-layer features require no new runtime dependencies (checked at
  every release).

## Release criteria

A version may ship when: the full unit + integration suites are green on the
whole matrix, both gemspecs build, `history.md` documents every user-facing
change since the last release, and the version constant and gemspec agree.
See [docs/operations/DELIVERY.md](docs/operations/DELIVERY.md).
