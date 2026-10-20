# REQUIREMENTS — traceability and acceptance criteria

Every product requirement has an ID, a testable acceptance criterion, the
specs that verify it, and a status. This is what turns "the code compiles"
into "the feature is done": an implementation is complete when its verifying
specs are green and its row says `implemented`. PRs that change behavior
must update the affected rows in the same change.

Status vocabulary: `implemented` (specs green in CI), `planned` (agreed,
not built), `in-progress` (branch work, not merged). Version markers note the
upstream rest-client release line in which a requirement landed; contractful
0.1.0 ships every row marked `implemented`.

## Core HTTP client

| ID | Requirement | Acceptance criterion (key) | Verified by | Status |
| --- | --- | --- | --- | --- |
| REQ-C01 | Verb one-liners (FR-1) | `Contractful.get/post/put/patch/delete/head/options` return a String-like `Response` | `spec/unit/contractful_spec.rb` | implemented (1.x) |
| REQ-C02 | Block form error suppression | With a block, non-2xx returns the response instead of raising | `spec/unit/request_spec.rb` | implemented (1.x) |
| REQ-C03 | Resource nesting (FR-2) | `Resource#[]` builds sub-paths sharing options | `spec/unit/resource_spec.rb` | implemented (1.x) |
| REQ-C04 | Payload forms (FR-3) | Hash → form; JSON style accepted; raw String passed through; multipart file parts stream correctly | `spec/unit/payload_spec.rb` | implemented (1.x) |
| REQ-C05 | ParamsArray (FR-4) | Repeated keys and `a[b]`-style nesting serialize in order | `spec/unit/params_array_spec.rb` | implemented (1.x) |
| REQ-C06 | Redirects (FR-7) | GET/HEAD followed by default up to `:max_redirects`; others raise unless `:max_redirects` set / block used; chain kept in `response.history` | `spec/unit/request_spec.rb` | implemented (1.x) |
| REQ-C07 | Cookies (FR-4) | Set-cookie captured into `#cookies`/`#cookie_jar`; jar replayed on follow-ups | `spec/unit/abstract_response_spec.rb` | implemented (1.x) |
| REQ-C08 | Proxy (FR-10) | ENV proxies used by default; per-request override and `:proxy => nil` opt-out | `spec/unit/request_spec.rb` | implemented (1.x) |

## Timeouts, TLS, retries, pooling

| ID | Requirement | Acceptance criterion (key) | Verified by | Status |
| --- | --- | --- | --- | --- |
| REQ-T01 | Phase timeouts (FR-5) | `:timeout`, `:open_timeout`, `:read_timeout`, `:write_timeout` all reach Net::HTTP | `spec/unit/request_spec.rb` | implemented (2.2) |
| REQ-T02 | SSL version normalization (FR-6) | `:TLSv1_2`-style symbols, `:TLS1_2`-style and integers all configure the same floor; no raw symbol reaches Ruby 4.0 OpenSSL | `spec/unit/request_spec.rb` | implemented (2.2) |
| REQ-T03 | CA control (FR-6) | `:ssl_ca_file` loads trust anchors; client cert/key accepted | `spec/integration/httpbin_spec.rb` | implemented (1.x) |
| REQ-T04 | Automatic retries (FR-11) | Retryable network failures and statuses (408/425/429/500/502/503/504) retried with exponential backoff from `:retry_interval`; payload rewound; `Retry-After` (seconds or HTTP-date) honored, capped by `:max_retry_after`, disabled via `retry_after: false` | `spec/unit/request_spec.rb`, `spec/unit/exceptions_spec.rb` | implemented (2.3/2.5) |
| REQ-T05 | Retryable classification (FR-20) | `Exception#retryable?` and `Exceptions.retryable?` classify statuses and network errors; 401/404/422 are terminal | `spec/unit/error_classification_spec.rb` | implemented (2.5) |
| REQ-T06 | Persistent connections (FR-12) | `persistent: true` reuses one pooled connection per host/SSL key; pool thread-safe; invalidation on broken connections; cert fingerprint part of the key | `spec/unit/connection_pool_spec.rb` | implemented (2.3) |
| REQ-T07 | Response JSON (FR-13) | `response.json` parses with forwarded options | `spec/unit/response_spec.rb` | implemented (2.3) |

## Errors and logging

| ID | Requirement | Acceptance criterion (key) | Verified by | Status |
| --- | --- | --- | --- | --- |
| REQ-E01 | Status exceptions (FR-8) | Every documented status maps to a rescueable class carrying `.response`, `.http_code`, `.http_body` | `spec/unit/exceptions_spec.rb` | implemented (1.x) |
| REQ-E02 | Timeout exceptions | Open/Read/Write timeout map to `Exceptions::OpenTimeout`/`ReadTimeout`/`WriteTimeout`, all `retryable?` | `spec/unit/exceptions_spec.rb` | implemented (2.x) |
| REQ-E03 | Logging hook (FR-9) | `Contractful.log=` / `CONTRACTFUL_LOG` route request/response log lines | `spec/unit/request_spec.rb` | implemented (1.x) |

## Contract-first layer

| ID | Requirement | Acceptance criterion (key) | Verified by | Status |
| --- | --- | --- | --- | --- |
| REQ-F01 | Contract declarations (FR-14) | `contract :name, 'VERB /path'` registers a `Definition`; invalid request lines/verbs/names raise `InvalidDefinition` at load | `spec/unit/contract/definition_spec.rb` | implemented (2.4) |
| REQ-F02 | Generated methods | Each contract defines `name(**params)`, `name_url(**params)`; paginated contracts add `name_pages`, `all_name` | `spec/unit/contract/definition_spec.rb`, `spec/unit/contract/pagination_spec.rb` | implemented (2.4/2.5) |
| REQ-F03 | Closed request schemas (FR-14) | Missing/unknown/invalid params raise `MissingParam`/`UnknownParam`/`InvalidParam` before any network traffic; strict mode default; constraints `inclusion:/min:/max:/length:/pattern:` enforced post-coercion | `spec/unit/contract/param_spec.rb`, `spec/unit/contract/executor_spec.rb` | implemented (2.4/2.5) |
| REQ-F04 | Param typing | String/Integer/Float/`:boolean`/Array/Hash/class/Proc coercion with `coerce: false` strictness and lazy-proc defaults | `spec/unit/contract/param_spec.rb` | implemented (2.4) |
| REQ-F05 | Response contracts (FR-15) | `responds` statuses/ranges + body type; declared error statuses return instead of raise; unexpected status/shape/type raises `UnexpectedResponse` with `.response` | `spec/unit/contract/response_validation_spec.rb` | implemented (2.4) |
| REQ-F06 | Open response schemas (FR-15) | `response_field` required+type bind; undeclared fields pass through; `inclusion:` only with `strict: true`; values never coerced | `spec/unit/contract/response_fields_spec.rb` | implemented (2.5) |
| REQ-F07 | Contract auth (FR-16) | `bearer:`/`api_key:`(single, array, `in: :query`)/`basic:`; callables invoked per request; `auth false` per contract; resolved before `before_request` | `spec/unit/contract/auth_spec.rb` | implemented (2.5) |
| REQ-F08 | Idempotency (FR-17) | `idempotent` injects `Idempotency-Key` (header/generator configurable), stable across retries; `_idempotency_key:` pins | `spec/unit/contract/idempotency_spec.rb` | implemented (2.5) |
| REQ-F09 | Pagination (FR-18) | Cursor and offset styles; `_pages` Enumerator validates each page; `all_*` flattens; `_max_pages` (default 1000) raises `PaginationError` | `spec/unit/contract/pagination_spec.rb` | implemented (2.5) |
| REQ-F10 | Rate-limit parsing (FR-19) | IETF `RateLimit-*` preferred over `X-RateLimit-*`; `response.rate_limit` nil when absent; `rate_limited?` strict; 429 falls back to `RateLimit-Reset` | `spec/unit/rate_limit_spec.rb` | implemented (2.5) |
| REQ-F11 | Callbacks (FR-21) | `before_request` mutates context pre-send; `after_response` post-validation; root-first accumulation | `spec/unit/contract/callbacks_spec.rb` | implemented (2.4) |
| REQ-F12 | CRUD macro (FR-22) | `resource :posts` generates list/get/create/update/delete contracts (non-strict) with only/except/update_with/path/singular options | `spec/unit/contract/resource_spec.rb` | implemented (2.4) |
| REQ-F13 | Reflection + dispatch (FR-22) | `contracts/contract_names/contract?/contract_for` on class and instance; `call_*`, `*_contract`, `has_*?` via `method_missing` with `respond_to_missing?` | `spec/unit/contract/introspection_spec.rb` | implemented (2.4) |
| REQ-F14 | Inheritance | Config, contracts, callbacks merge down the ancestor chain; nearest definition wins | `spec/unit/contract/definition_spec.rb`, `spec/unit/contract/callbacks_spec.rb` | implemented (2.4) |
| REQ-N01 | OpenAPI import helper | `OpenAPIImport.import` converts an OpenAPI 3.x document into Definitions (types, constraints, payload styles, statuses, response fields); every lossy mapping is reported on `#notes`; `to_ruby` output re-evaluates to contracts that `describe` identically; opt-in require, zero runtime deps | `spec/unit/contract/openapi_import_spec.rb` | implemented (2.6) |
| REQ-N02 | Recorded-sequence test helper | `Sequence.load` validates a fixture against the client's contracts (unknown calls/keys rejected at load); `run` replays each recorded response through the contract pipeline under WebMock and raises `Failure` on the first violation with the step number; `before_step`/`after_step` hooks carry stateful rules; `expect_request` pins outgoing path/query/headers/payload subsets | `spec/unit/contract/sequence_spec.rb` | implemented (2.6) |

| REQ-N04 | Event notifications | `Notifications.subscribe` receives `request`/`response`/`retry` events with method, url, attempt, status, duration and retry cause; subscribers that raise are logged and skipped; `clear!` detaches all; the ActiveSupport bridge re-posts every event as `contractful.<name>` (opt-in require, activesupport not a runtime dep) | `spec/unit/notifications_spec.rb`, `spec/unit/notifications_active_support_spec.rb` | implemented (0.1.0) |
| REQ-R01 | Retry jitter | `retry_jitter: :full/:equal/:decorrelated` randomizes computed backoff (Retry-After delays untouched); `:decorrelated` samples [retry_interval, min(cap, previous*3)] with `retry_jitter_cap` (default 30); `retry_rng` injects randomness (seeded Random = deterministic tests); contract layer passes `_retry_jitter`/`_retry_jitter_cap`/`_retry_rng` | `spec/unit/retry_jitter_spec.rb` | implemented (0.1.0) |
| REQ-R02 | Circuit breaker | `breaker: true/{threshold:, cooldown:}` opens a host-level circuit (scheme/host/port key, process-wide, thread-safe) after N consecutive failure requests (network errors + retryable statuses; 4xx is success), fails fast with `CircuitOpenError` (retryable? false) during cooldown, half-open probe decides next state; transitions post `circuit` notifications; contract layer passes `_breaker` | `spec/unit/circuit_breaker_spec.rb` | implemented (0.1.0) |
| REQ-R03 | Rate-limit pacing | `pace: true/{limit:, window:, max_wait:}` enforces a process-wide per-host sliding window before transmit (retries acquire per attempt); a full window sleeps and posts a `pace` notification; a wait beyond `max_wait` raises `PacingTimeout`; contract layer passes `_pace` | `spec/unit/pacer_spec.rb` | implemented (0.1.0) |
| REQ-R04 | OAuth2 refresh-on-401 | `auth token_provider:` accepts an object answering #token/#refresh (validated at definition time); resolves as Bearer per request; a 401 triggers a one-flight refresh (per-provider mutex, `token_refresh` notification) and exactly one retry with the fresh credential — no refresh loop | `spec/unit/contract/token_refresh_spec.rb` | implemented (0.1.0) |
## Platform, packaging, compatibility

| ID | Requirement | Acceptance criterion (key) | Verified by | Status |
| --- | --- | --- | --- | --- |
| REQ-P01 | Ruby range (FR-24) | Suite green on 3.0–4.0 matrix; `ruby >= 3.0` enforced by gemspec | CI matrix | implemented (2.2) |
| REQ-P02 | Windows gem (FR-23) | `contractful.windows.gemspec` builds for `x64-mingw-ucrt` with `ffi ~> 1.16` root-cert loading | `spec/unit/windows/root_certs_spec.rb`, gem build | implemented (2.2) |
| REQ-P03 | Packaging integrity | Both gemspecs build from a clean checkout; `git ls-files` file list; metadata includes changelog/bugs URIs | gem build in release checklist | implemented (2.2) |
| REQ-P04 | CI gates | Every push runs unit + integration specs on the matrix; `permissions: contents: read` | `.github/workflows/ci.yml` | implemented (2.2) |

## Planned

| ID | Requirement | Acceptance criterion (key) | Status |
| --- | --- | --- | --- |
| REQ-N03 | Tags for 2.4.0/2.5.0 after PR #2 merge | `v2.4.0`, `v2.5.0` tags exist on master post-merge | planned |

Planned items live in [docs/implementation/IMPLEMENTATION_PLAN.md](docs/implementation/IMPLEMENTATION_PLAN.md); they become `in-progress` only when a branch opens.
