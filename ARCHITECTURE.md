# ARCHITECTURE — System architecture

contractful is a layered Ruby library with a deliberately thin core: one
request pipeline used by every entry point, a transport that is Net::HTTP,
and a metaprogrammed contract layer that compiles declarations into real
methods on top of that pipeline. There is no runtime, no daemon, no external
service dependency — the gem is loaded into the host process and makes HTTP
calls on demand.

## Layer diagram

```text
┌────────────────────────────────────────────────────────────┐
│ Contract layer — Contractful::Contract                     │
│   DSL macros → Definition → Executor → define_method      │
│   typed params · response contracts · auth · idempotency   │
│   pagination · rate-limit · callbacks · reflection         │
├────────────────────────────────────────────────────────────┤
│ High-level API — Contractful.get/post/... · Resource        │
├────────────────────────────────────────────────────────────┤
│ Request pipeline — Contractful::Request                     │
│   payload normalization (Payload, ParamsArray)             │
│   auth (user/password, netrc) · cookies · redirects        │
│   retries + backoff · Retry-After · connection pool        │
├────────────────────────────────────────────────────────────┤
│ Transport — Net::HTTP + OpenSSL                            │
│   ssl_min/max_version normalization · timeouts             │
├────────────────────────────────────────────────────────────┤
│ Response side — AbstractResponse · Response · RawResponse  │
│   headers · history · #json · RateLimit parsing            │
├────────────────────────────────────────────────────────────┤
│ Errors — Contractful::Exception hierarchy                   │
│          Contractful::Contract::Error hierarchy             │
└────────────────────────────────────────────────────────────┘
```

## Module map

| Module | Responsibility |
| --- | --- |
| `lib/contractful.rb` | Facade: module-level verb methods, `Contractful.log`, version |
| `request.rb` | The pipeline: option validation, payload/params prep, transmission, redirects, retries, timeouts, SSL setup |
| `payload.rb` | Payload normalization: form, JSON, raw, multipart, streaming; `rewind` for retries |
| `params_array.rb` | Ordered param lists with repeated keys and nested notation |
| `resource.rb` | ActiveResource-style wrapper around `Request` |
| `abstract_response.rb` | Shared response behavior: headers, code, cookies, history |
| `response.rb` | Concrete String-like response body with `.json`, `.rate_limit` |
| `raw_response.rb` | File-backed response for streaming downloads |
| `connection_pool.rb` | Thread-safe keep-alive pool (`persistent: true`) |
| `rate_limit.rb` | IETF `RateLimit-*` / legacy `X-RateLimit-*` parsing |
| `exceptions.rb` | Status→exception map, `RETRIABLE_STATUSES`, `Exceptions.retryable?` |
| `contract.rb` | Contract error hierarchy + the `include` hook wiring the DSL |
| `contract/dsl.rb` | Class macros (`base`, `contract`, `resource`, `auth`, ...), `define_method` generation, reflection |
| `contract/definition.rb` | One operation: params, responses, path expansion |
| `contract/param.rb` | Typed param: coercion + closed-schema constraints (`min/max/length/pattern/inclusion`) |
| `contract/response_field.rb` | Open-schema response field bindings |
| `contract/auth.rb` | `bearer:` / `api_key:` / `basic:` resolution to headers |
| `contract/pagination.rb` | Cursor/offset iteration + `PaginationError` guard |
| `contract/executor.rb` | Per-call execution: validate → build → send → verify → callbacks |
| `contract/config.rb` | Per-class config objects + ancestor-chain merging |
| `windows/root_certs.rb` | Windows certificate store loading (separate platform gem) |

## Request lifecycle

1. **Entry.** A call arrives: `Contractful.get`, `Resource#get`, or a
   generated contract method (`Contract::Executor.call`).
2. **Contract validation (contract path only).** Params are coerced and
   checked against the `Definition` — required, type, `inclusion:`,
   `min/max/length/pattern`, strict unknown-param rejection. Any violation
   raises (`MissingParam`/`UnknownParam`/`InvalidParam`) **before** the
   network is touched. Path placeholders are expanded and URI-escaped;
   remaining params are routed to query string or JSON/form payload by verb
   and `payload_style`.
3. **Request assembly.** `Request` validates options, normalizes the payload
   (`Payload::Base` family), merges headers, resolves auth (contract auth
   first, then `before_request` callbacks may adjust everything through the
   mutable context), loads netrc credentials, and applies cookies.
4. **Connection.** With `persistent: true` the request checks a connection
   out of `Contractful::ConnectionPool` (keyed by host/port/proxy/SSL); the
   key must include the client-certificate fingerprint so credentials never
   leak across pool entries. Otherwise a fresh `Net::HTTP` is configured:
   SSL versions normalized via `normalize_ssl_version`, timeouts applied
   (`open/read/write`), proxy resolved from options or ENV.
5. **Transmission with retries.** The request transmits; on a retryable
   network failure (`Timeout`, `ECONNRESET`, `EPIPE`, ...) or a retryable
   HTTP status (408, 425, 429, 500, 502, 503, 504) and `:max_retries > 0`,
   it waits — honoring `Retry-After` (delta or HTTP-date, capped by
   `:max_retry_after`) or exponential backoff — rewinds the payload and
   retries with any idempotency key kept stable.
6. **Response validation.** Classic path: non-2xx raises the mapped
   exception (`Contractful::NotFound`, ...) with the response attached.
   Contract path: the status must be in the declared set, the body must
   satisfy the declared type and `response_field` bindings, and any
   `verify_response` block must pass — otherwise
   `Contract::UnexpectedResponse` (with the response attached). Declared
   error statuses are returned as values instead of raised (redirects still
   followed); contracts without declarations keep classic behavior.
7. **Delivery.** `after_response` callbacks observe the validated response;
   rate-limit headers are parsed onto `response.rate_limit`; the connection
   is checked back in; the response (or collected page) returns to the
   caller.

## Deliberate architecture decisions

- **Net::HTTP is the only transport.** No pluggable transport abstraction
  exists today; the per-request meta options (`_persistent`, `_timeout`,
  ...) and SSL normalization are typed against what Net::HTTP actually
  supports. This keeps the surface honest — see ADR
  [0002](adr/0002-contract-first-client-layer.md) for why the contract layer
  also avoids a schema-engine dependency.
- **Generated methods are real methods.** Contract execution is compiled
  with `define_method` at declaration time — `method_missing` handles only
  the convenience families (`call_*`, `*_contract`, `has_*?`) with
  `respond_to_missing?` support. See ADR
  [0003](adr/0003-metaprogrammed-client-generation.md).
- **One global mutable, thread-safe resource:** the default connection pool.
  Everything else is per-request or per-client-class state.
- **`frozen_string_literal: true` everywhere**; request/response objects
  never mutate caller-supplied option hashes.

## Development-time architecture

- **Tests:** RSpec, WebMock for offline integration; contract specs mirror
  the DSL surface under `spec/unit/contract/`; a small live suite against
  httpbin.org runs in CI (see
  [docs/engineering/TESTING.md](docs/engineering/TESTING.md)).
- **CI:** GitHub Actions matrix Ruby 3.0→4.0 + experimental `ruby-head`,
  `permissions: contents: read`
  ([.github/workflows/ci.yml](.github/workflows/ci.yml)).
- **Packaging:** two gemspecs from one source — the Ruby platform gem and
  the Windows gem (`ffi`-based root certificate store, `x64-mingw-ucrt`).

The security architecture — trust boundaries, TLS posture, threat model —
lives in [docs/security/THREAT_MODEL.md](docs/security/THREAT_MODEL.md).
