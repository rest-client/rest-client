# 0.1.0

First release published as **contractful**. The version restarts at 0.1.0
because the gem name changed: the `rest-client` name on RubyGems belongs to
the original project this codebase modernized, and none of the versions
below were ever published under it. The code itself is the current master
line — same contracts, helpers and test suite — renamed:

* Renamed the gem, the require path and the module: `rest-client` →
  `contractful`, `require 'restclient'` → `require 'contractful'`,
  `RestClient` → `Contractful`, and the CLI with it (`bin/contractful`).
  The backward-compat entry shims (`rest-client.rb`, `rest_client.rb`) are
  gone along with the old-name requires they existed for.
* `RESTCLIENT_LOG` → `CONTRACTFUL_LOG`.
* The GitHub repository moved to
  [shubhamtaywade82/contractful](https://github.com/shubhamtaywade82/contractful);
  old links redirect. Gemspec metadata, badges and the documentation set
  point at the new location.
* References to the upstream rest-client repository — issue/PR links in
  code comments and the heritage notes — deliberately keep pointing at the
  original project.
* The unit suite now runs under simplecov and enforces a 95% line-coverage
  minimum on `lib/` as CI gate G13 (the `windows/` platform shims and
  `version.rb` — which Bundler evaluates before a coverage tracer can
  attach — are filtered with the cause documented in `spec/spec_helper.rb`).
  Closing the measured gaps added edge-branch specs for `Param` coercion and
  the OpenAPI import, and surfaced two latent defects that are fixed here:
  the `Param` Kernel-cast fallback crashed with `NoMethodError` on anonymous
  classes (now cleanly rejected with `InvalidParam`), and the OpenAPI
  renderer's "cannot render a Proc default" guard was dead code because
  `Param#default_value` resolves procs — the guard now keys off the new
  `Param#lazy_default?` predicate.
* The gem now ships YARD API documentation: `.yardopts` configures the
  rendering (markdown, README/history as narrative files, protected
  methods included), the `Contractful` facade module carries a proper
  overview doc, and the gemspec links `documentation_uri` to rubydoc.info.
  `yard` and `redcarpet` are development-only gems.

* Post request lifecycle events to a new `Contractful::Notifications` hub
  (`request`, `response`, `retry` — method, url, attempt, status,
  duration_ms, retry cause). Thread-safe; a raising subscriber is logged
  and skipped so observability cannot break the request it observes. An
  opt-in `contractful/notifications/active_support` bridge re-posts every
  event to ActiveSupport::Notifications as `contractful.<name>`;
  activesupport is a test-only dependency, never a runtime one.
* Randomize computed retry backoff with `retry_jitter: :full`, `:equal` or
  `:decorrelated` (AWS recipe, capped by `retry_jitter_cap`) so fleets of
  clients do not retry in lockstep; a server's Retry-After is honored
  exactly, and `retry_rng` accepts a seeded Random for deterministic
  tests. Contract clients pass the options through as
  `_retry_jitter`/`_retry_jitter_cap`/`_retry_rng`.
* Add an opt-in host-level circuit breaker (`breaker: true` or a config
  Hash): consecutive failure requests — network errors and retryable
  statuses after retries are exhausted — open a process-wide
  scheme/host/port circuit that fails fast with
  `Contractful::CircuitOpenError` for the cooldown, then half-open probes.
  4xx responses never open a circuit. Transitions post `circuit`
  notifications; contract clients pass `_breaker` per call.
* Add proactive rate-limit pacing (`pace: true` or a config Hash): a
  process-wide sliding window per scheme/host/port delays requests that
  would exceed a configured quota instead of eating 429s — waits post
  `pace` notifications and a wait beyond `max_wait` raises
  `PacingTimeout`. Contract clients pass `_pace` per call.
* Add OAuth-style token-provider auth (`auth token_provider:`): the
  provider answers `#token` and `#refresh`; on a 401 the executor
  refreshes it in one flight (concurrent 401s share a single refresh)
  and retries exactly once with the fresh credential.

Review follow-up (second pass over the request pipeline and contract layer):

* Redirects now strip `Authorization`, `Proxy-Authorization` and `Cookie`
  headers when the origin changes, and refuse HTTPS→HTTP downgrades, so
  credentials cannot follow a redirect to a different host.
* Treat every 2xx status (including 208 and 226) as success. Retryable HTTP
  statuses are retried in the block/error-suppression path too, and the
  circuit breaker judges the actual response even when the block returns a
  different value; an unknown or absent response no longer counts as a
  success.
* Token-provider refresh now applies to undeclared 401 responses and honors
  `auth false`. Circuit-breaker transitions are posted outside the lock, so
  subscribers can safely inspect the breaker.
* Redact URL passwords from notifications and `Request#inspect` as well as
  logs, and use the documented `<<` interface when logging a failing
  notification subscriber.
* Non-seekable payload streams are no longer consumed by request logging and
  report as non-rewindable instead of raising `Errno::ESPIPE`;
  `Payload.generate` no longer mutates the caller's `:multipart` flag.
* OpenAPI exclusive bounds shift by one only for integer schemas; number
  schemas use an inclusive approximation with a note.
* Sequence fixtures treat false/nil payload values as present and anchor
  stub paths so a prefix does not match a longer path.
* Live-network integration specs are tagged and excluded by default; run
  them explicitly with `LIVE_HTTP_TESTS=1` or `rake spec:live`.
* Documentation now keeps module helpers header-only (resilience options go
  through `Contractful::Request.execute`), aligns URL-credential redaction
  guidance with the implementation, and removes stale version labels.

# 2.6.0

Roadmap-helpers release: the two planned development-time companions to
the contract-first layer (REQ-N01, REQ-N02), plus the documentation suite
and the review-hardening fixes that landed on master ahead of the release.

* Add the project documentation suite: `AGENTS.md`, `CONTRIBUTING.md`,
  `PRD.md`, `DESIGN.md`, `ARCHITECTURE.md`, `API.md`, `DATABASE.md` at the
  root, plus `docs/` with the requirements traceability matrix,
  architecture decision records (0001–0003), implementation plan and setup
  guide, engineering guides (testing, quality gates, error handling,
  integrations), security documents (threat model, agent tool policy),
  operations guides (delivery, observability, runbook) and the agent
  workflow playbook.
* Fix the `spec:unit` rake task to use the `spec/unit/**/*_spec.rb` glob —
  the previous pattern skipped the nested `spec/unit/contract/` directory,
  so the contract-first suite never ran under CI's unit job.
* Add the OpenAPI import helper (REQ-N01): an opt-in, development-time
  reader (`require 'contractful/contract/openapi_import'`) that converts an
  OpenAPI 3.x document into `contract` definitions — typed closed-schema
  params with enum/min/max/length/pattern constraints, `payload_style`
  inference, response statuses (including `2XX` wildcards), JSON body
  types and open-schema `response_field` bindings. A notes channel reports
  every lossy mapping decision (header params, multipart bodies, `oneOf`
  unions, `default` responses) instead of guessing, `to_ruby` renders a
  ready-to-paste client class from the built definitions, and the
  generated source round-trips through `Definition#describe`.
* Add the recorded-sequence test helper (REQ-N02): an opt-in, test-only
  module (`require 'contractful/contract/sequence'`) that replays recorded
  vendor response sequences through a contract client under WebMock. Each
  fixture step stubs its recorded response, invokes the contract method
  and runs the contract's own validation — the first violation fails with
  the step number attached. `expect_request` assertions pin outgoing
  paths, query params, headers and JSON payload subsets (unknown keys are
  rejected at load time); `before_step`/`after_step` hooks carry the
  stateful rules contracts cannot express (token refresh sequencing,
  rate-limit windows, cross-step invariants).
Review-hardening fixes from a skills-based code review (secret redaction,
contract layer robustness, spec hygiene). No public API changes.

* Redact credential-bearing request headers from the request log. The
  request log line (`Contractful.get "http://...", "Accept"=>...`) now
  renders `Authorization`, `Proxy-Authorization` and `Cookie` values as
  `[REDACTED]`, honoring the promise in
  `docs/operations/OBSERVABILITY.md` ("auth headers are not logged") and
  closing the T5 credential-leakage path in the threat model. Non-credential
  headers are logged exactly as before.
* Use the redacted URL in raw-response streaming progress logs. The
  `streaming GET ... % done` lines previously logged the raw URL, leaking
  basic-auth credentials embedded in the URL; every other log line already
  used the redacted form.
* Fix a `TypeError` ("no implicit conversion of nil into Hash") raised from
  `__contract_effective_headers` when a contract client subclass defines
  its own `initialize` without calling `super`.
* Bound the custom-class param coercion fallback to Kernel casts. The last
  resort cast in `Contractful::Contract::Param` used to `send` a method
  named after the type class on the param object itself (unbounded dynamic
  dispatch); it now only attempts public `Kernel` module functions
  (`Float`, `Complex`, ...).
* Harden `Payload::Multipart#boundary` against frozen `SecureRandom.base64`
  return values: the `+`/`/` -> `A`/`B` substitution no longer mutates the
  generated string in place, so the boundary can be built even when the
  generated string is frozen.
* Enforce the repo hard rule "`frozen_string_literal: true` at the top of
  every file under `lib/` and `spec/`" for the 19 spec files that were
  still missing the magic comment, and adjust the few specs that mutated
  frozen literals in place (`String#force_encoding` on literals now goes
  through `.dup`).
* Remove an unused variable warning in the idempotency spec.
* Guard `Payload::Base#to_s` against non-seekable streams: the rewind after
  reading used to raise `NoMethodError` (reader objects without `#seek`) or
  `Errno::ESPIPE` (pipes, sockets), which crashed `Request#log_request` for
  small streamed payloads; non-rewindable streams are now left positioned at
  EOF, mirroring the defensive `Payload#rewind` contract.
* Resolve case-insensitive header collisions in `make_headers`: a user header
  spelled `'content-type'` now replaces (instead of coexisting with) the
  default `'Content-Type'`, so duplicate headers no longer reach the wire, and
  the payload-override and Cookie-override warnings fire across casings.
  String header keys still pass through verbatim (rest-client 1.x/2.x
  compatibility, upstream issue #599); both behaviors are pinned by specs.
* Document the finalized design decisions from the repository review in
  `docs/adr/0004-review-observations-resolution.md` (non-seekable payload
  logging, string header passthrough, connection pool without a checkout cap,
  and the frozen `Response < String` / response-block arity API), with an
  API-freeze note at the response-block call site.
* Shrink the RuboCop baseline from 197 cops / 4,766 quarantined offenses to
  81 cops / ~2,100: all safe autocorrections applied (whitespace, literal
  style, safe refactors) plus hand fixes for the non-correctable lint and
  naming findings (constant renames `SSL_OPTION_LIST`/`WINDOWS_PLATFORMS`,
  rescue-variable renames, real documentation comments for the previously
  undocumented modules, duplicated-branch merge in the contract DSL). Four
  intentional patterns moved out of the auto-generated todo into documented
  `.rubocop.yml` entries (rescue ::Exception around pool invalidation, the
  to_ruby eval sandbox, symbol numbering like `:TLSv1_2`, and the public
  `has_file?`/`has_default?` predicate names). The stdout/stderr log devices
  now write via `$stdout`/`warn` so logging follows a reassigned `$stdout`,
  and the log specs assert captured output instead of spying on IO methods.

# 2.5.0

Feature release completing the contract-first layer: closed request
schemas, open response schemas, contract-declared auth, idempotency keys,
pagination and rate-limit awareness — the pieces a contract needs to carry
beyond shapes.

* Add closed-schema param constraints: `min:` / `max:` (inclusive bounds on
  any Comparable), `length:` (exact Integer or Range over String/Array/Hash)
  and `pattern:` (Regexp on Strings). Constraints are enforced after
  coercion — `param :quantity, Integer, min: 1` rejects the string "0"
  exactly like the integer 0 — and every violation raises `InvalidParam`
  before any HTTP request is built.
* Add `response_field`: per-field response bindings with open-schema
  semantics. Required fields and their types bind (missing, null or
  type-mismatched fields raise `UnexpectedResponse` on return), while
  undeclared fields are additive data and `inclusion:` sets are not
  enforced unless `strict: true` — a new enum member the client does not
  know about yet is data, not an error. Values are never coerced.
* Add contract-declared auth: `auth bearer:`, `auth api_key:` (single or
  multiple entries, header or query location — the dual-header style) and
  `auth basic:`. Credentials may be literals or callables; callables are
  invoked per request so short-lived tokens stay fresh. Auth is resolved
  before the `before_request` callbacks (which can still override it),
  inherits down the class chain, and individual contracts can opt out with
  `auth false`.
* Add retryable vs terminal error classification:
  `Contractful::Exceptions::RETRIABLE_STATUSES` (408, 425, 429, 500, 502,
  503, 504), `Exception#retryable?` and `Exceptions.retryable?` (which also
  classifies plain network errors like `SocketError`/`Errno::*`). Requests
  now retry retryable HTTP statuses — not just network failures — when
  `:max_retries` is positive, honoring the server's `Retry-After` header
  (delta-seconds or HTTP-date, capped by the new `:max_retry_after`
  option, default 60), including inside the block/error-suppression path.
  Opt out with `retry_after: false`.
* Add idempotency keys: flag a contract `idempotent` and every call carries
  an `Idempotency-Key` header (header name and generator configurable at
  class level, per-call key via `_idempotency_key:`), generated once per
  logical call and stable across automatic retries — which is what makes
  retrying POSTs safe.
* Add pagination contracts: `paginated style: :cursor, cursor_param:,
  next_cursor_path:, items_path:` or `style: :offset, offset_param:,
  limit_param:, has_more_path:`. Every paginated contract gets two
  metaprogrammed methods — `#{name}_pages` (lazy Enumerator of validated
  page responses) and `all_#{name}` (flat collector). A `_max_pages` guard
  (default 1000) raises `Contractful::Contract::PaginationError` instead of
  looping forever, and page 1 can resume from an explicitly supplied
  cursor or offset.
* Add rate-limit header parsing: `Contractful::RateLimit` reads the IETF
  `RateLimit-*` headers and the legacy `X-RateLimit-*` convention
  (preferring IETF), handling integer/HTTP-date/epoch resets and the
  "limit, limit;w=window" description form. Every response exposes
  `response.rate_limit` (nil when the server sends no headers — data
  absence, not an error) and `response.rate_limited?` (429 or exhausted
  quota). A 429 without `Retry-After` falls back to the `RateLimit-Reset`
  window before exponential backoff.

# 2.4.0

Feature release adding a contract-first architecture layer with heavy
metaprogramming on top of the classic contractful API.

* Add `Contractful::Contract`: declare API operations as contracts —
  `contract :name, 'VERB /path'` with an `instance_eval`'d DSL block — and
  the gem generates the client methods (`define_method`), `#{name}_url`
  path builders, parameter validation and a reflection API for you. The
  contract *is* the implementation.
* Add a typed parameter engine: `String`, `Integer`, `Float`, `:boolean`,
  `Array`, `Hash`, arbitrary classes (`is_a?` check, then
  `Class#contractful_coerce`, then a Kernel cast) and `Proc` coercions, with
  `required:`, `default:` (lazy procs supported), `inclusion:` and
  `coerce: false` strict mode. Path placeholders (`:owner`, `:repo`) are
  auto-synthesized as required params, URI-escaped and consumed out of the
  query/payload. Violations raise `MissingParam`, `UnknownParam` or
  `InvalidParam` with precise messages before any HTTP traffic happens.
* Add response contracts: `responds 200, 404, type: Hash` declares expected
  statuses (Integers or Ranges) and an optional JSON body type
  (`:array`/`:hash`/`:string`/`:json`/any class). Declaring 4xx/5xx statuses
  suppresses the default exception behavior for that contract — expected
  error responses become normal return values (redirects are still
  followed). Violations raise `UnexpectedResponse` with the response
  attached. `verify_response` blocks add custom assertions and receive the
  JSON-parsed body when declared with two parameters.
* Add `before_request` / `after_response` callbacks: `before_request`
  receives a mutable execution context (changing it changes the outgoing
  request), `after_response` receives the validated response. Both
  accumulate down the class inheritance chain, root-most first.
* Add the `resource :posts` macro: metaprograms the five standard REST
  CRUD contracts (`list_posts`, `get_post`, `create_post`, `update_post`,
  `delete_post`) with `only:`/`except:` filters, `update_with: :put`,
  `path:` override and a small English singularizer (`singular:` override).
  Generated CRUD contracts accept free-form attributes via the new
  per-contract `strict_params` override.
* Add reflection and dynamic dispatch: `.contracts`, `.contract_names`,
  `.contract?`, `.contract_for` (class and instance level,
  inheritance-aware) plus `method_missing`-powered `call_#{name}`,
  `#{name}_contract` and `has_#{name}?` with `respond_to_missing?` support.
* Add per-call meta options for contracts (`_headers`, `_timeout`,
  `_open_timeout`, `_read_timeout`, `_write_timeout`, `_persistent`,
  `_max_retries`, `_retry_interval`) and instance-level overrides via
  `MyAPI.new(base:, headers:)`.

# 2.3.0

Feature release building on the 2.2.0 modernization.

* Add `Response#json`: parse the response body as JSON with a single call
  (`response.json`, or `response.json(symbolize_names: true)`). Keyword
  arguments are forwarded to `JSON.parse`.
* Add optional persistent connections (HTTP keep-alive): pass
  `persistent: true` to reuse the underlying connection across requests via
  the new thread-safe `Contractful::ConnectionPool` (also available as
  `Contractful.connection_pool`). Connections are pooled per host/proxy/SSL
  settings, never shared concurrently, discarded after network failures, and
  re-established when the server closed them.
* Add automatic retries: pass `:max_retries` (plus the optional
  `:retry_interval`, default 0.5s) to retry requests after transient network
  failures — connection/read/write timeouts, broken connections, connection
  resets and broken pipes — with exponential backoff. HTTP error responses are
  never retried, and payloads are rewound between attempts (non-rewindable
  payload streams disable retrying).
* Add `Contractful::Exceptions::WriteTimeout`, raised when `Net::WriteTimeout`
  fires. Previously a write timeout leaked a raw `Net::WriteTimeout` (or was
  misclassified as a read timeout), so the three timeout phases now share the
  common `Contractful::Exceptions::Timeout` rescue target.

# 2.2.0

Modernization release, reviving the gem after the upstream repository was
archived in 2019. The public API is unchanged; this release is about modern
Ruby support, tooling, and a few new request options.

* Support and CI-test Ruby 3.0, 3.1, 3.2, 3.3, 3.4, 4.0 and ruby-head
  (experimental). `required_ruby_version` is now `>= 3.0`.
* Add a `:write_timeout` request option, mapping to `Net::HTTP#write_timeout`,
  to bound time spent sending request bodies.
* Add `:ssl_min_version` and `:ssl_max_version` request options, mapping to
  `OpenSSL::SSL::SSLContext#min_version=` / `#max_version=`. This is the modern
  way to constrain TLS protocol versions (for example `:ssl_min_version =>
  :TLSv1_2`), complementing the legacy `:ssl_version` option.
* Reject URIs whose hostname is empty (Ruby 3.4+ returns `''` rather than `nil`
  for URLs like `http:///`).
* Remove the legacy Ruby 2.0 code paths from `Contractful::Utils`
  (`deprecated_cgi_parse_header` and friends); `HTTP::Accept` is now always
  used for Content-Type parsing.
* Add `# frozen_string_literal: true` to all library files.
* Modernize the gemspec: remove the deprecated `test_files` field, add gem
  metadata (`changelog_uri`, `bug_tracker_uri`, `rubygems_mfa_required`), point
  the homepage at this maintained fork, and refresh development dependencies
  (rspec ~> 3.13, webmock >= 3.19 < 5, pry ~> 0.14, rdoc >= 6.0). Drop the
  stale rubocop 0.49 / pry-doc development dependencies; rubocop tooling can be
  reintroduced later alongside a dedicated style pass.
* Fix the Windows gemspec to work when evaluated by modern Bundler, bump its
  ffi dependency to `~> 1.16`, and add the modern `x64-mingw-ucrt` platform.
* Replace the dead Travis CI setup with a GitHub Actions workflow that runs the
  unit and integration suites across the supported Ruby matrix.
* Update the integration test CA fixtures: www.mozilla.org now chains to Let's
  Encrypt (ISRG Root X1) rather than DigiCert, so the bundled root certificate
  and capath fixtures were replaced.
* Update specs for Ruby 3+ keyword-argument semantics (rspec-mocks now treats
  bare `with(...)` hashes as keyword arguments) and for Ruby 4.0 removing the
  `base64` gem from the default gems.
* The default `rake` task now runs the test suite.

# 2.1.0

- Add a dependency on http-accept for parsing Content-Type charset headers.
  This works around a bad memory leak introduced in MRI Ruby 2.4.0 and fixed in
  Ruby 2.4.2. (#615)
- Use mime/types/columnar from mime-types 2.6.1+, which is leaner in memory
  usage than the older storage model of mime-types. (#393)
- Add `:log` option to individual requests. This allows users to set a log on a
  per-request / per-resource basis instead of the kludgy global log. (#538)
- Log request duration by tracking request start and end times. Make
  `log_response` a method on the Response object, and ensure the `size` method
  works on RawResponse objects. (#126)
  - `# => 200 OK | text/html 1270 bytes, 0.08s`
  - Also add a new `:stream_log_percent` parameter, which is applicable only
    when `:raw_response => true` is set. This causes progress logs to be
    emitted only on every N% (default 10%) of the total download size rather
    than on every chunk.
- Drop custom handling of compression and use built-in Net::HTTP support for
  supported Content-Encodings like gzip and deflate. Don't set any explicit
  `Accept-Encoding` header, rely instead on Net::HTTP defaults. (#597)
  - Note: this changes behavior for compressed responses when using
    `:raw_response => true`. Previously the raw response would not have been
    uncompressed by contractful, but now Net::HTTP will uncompress it.
- The previous fix to avoid having Netrc username/password override an
  Authorization header was case-sensitive and incomplete. Fix this by
  respecting existing Authorization headers, regardless of letter case. (#550)
- Handle ParamsArray payloads. Previously, contractful would silently drop a
  ParamsArray passed as the payload. Instead, automatically use
  Payload::Multipart if the ParamsArray contains a file handle, or use
  Payload::UrlEncoded if it doesn't. (#508)
- Gracefully handle Payload objects (Payload::Base or subclasses) that are
  passed as a payload argument. Previously, `Payload.generate` would wrap a
  Payload object in Payload::Streamed, creating a pointlessly nested payload.
  Also add a `closed?` method to Payload objects, and don't error in
  `short_inspect` if `size` returns nil. (#603)
- Test with an image in the public domain to avoid licensing complexity. (#607)

# 2.0.2

- Suppress the header override warning introduced in 2.0.1 if the value is the
  same. There's no conflict if the value is unchanged. (#578)

# 2.0.1

- Warn if auto-generated headers from the payload, such as Content-Type,
  override headers set by the user. This is usually not what the user wants to
  happen, and can be surprising. (#554)
- Drop the old check for weak default TLS ciphers, and use the built-in Ruby
  defaults. Ruby versions from Oct. 2014 onward use sane defaults, so this is
  no longer needed. (#573)

# 2.0.0

This release is largely API compatible, but makes several breaking changes.

- Drop support for Ruby 1.9
- Allow mime-types as new as 3.x (requires ruby 2.0)
- Respect Content-Type charset header provided by server. Previously,
  contractful would not override the string encoding chosen by Net::HTTP. Now
  responses that specify a charset will yield a body string in that encoding.
  For example, `Content-Type: text/plain; charset=EUC-JP` will return a String
  encoded with `Encoding::EUC_JP`. (#361)
- Change exceptions raised on request timeout. Instead of
  `Contractful::RequestTimeout` (which is still used for HTTP 408), network
  timeouts will now raise either `Contractful::Exceptions::ReadTimeout` or
  `Contractful::Exceptions::OpenTimeout`, both of which inherit from
  `Contractful::Exceptions::Timeout`. For backwards compatibility, this still
  inherits from `Contractful::RequestTimeout` so existing uses will still work.
  This may change in a future major release. These new timeout classes also
  make the original wrapped exception available as `#original_exception`.
- Unify request exceptions under `Contractful::RequestFailed`, which still
  inherits from `ExceptionWithResponse`. Previously, HTTP 304, 401, and 404
  inherited directly from `ExceptionWithResponse` rather than from
  `RequestFailed`. Now _all_ HTTP status code exceptions inherit from both.
- Rename the `:timeout` request option to `:read_timeout`. When `:timeout` is
  passed, now set both `:read_timeout` and `:open_timeout`.
- Change default HTTP Accept header to `*/*`
- Use a more descriptive User-Agent header by default
- Drop RC4-MD5 from default cipher list
- Only prepend http:// to URIs without a scheme
- Fix some support for using IPv6 addresses in URLs (still affected by Ruby
  2.0+ bug https://bugs.ruby-lang.org/issues/9129, with the fix expected to be
  backported to 2.0 and 2.1)
- `Response` objects are now a subclass of `String` rather than a `String` that
  mixes in the response functionality. Most of the methods remain unchanged,
  but this makes it much easier to understand what is happening when you look
  at a Contractful response object. There are a few additional changes:
  - Response objects now implement `.inspect` to make this distinction clearer.
  - `Response#to_i` will now behave like `String#to_i` instead of returning the
    HTTP response code, which was very surprising behavior.
  - `Response#body` and `#to_s` will now return a true `String` object rather
    than self. Previously there was no easy way to get the true `String`
    response instead of the Frankenstein response string object with
    AbstractResponse mixed in.
  - Response objects no longer accept an extra request args hash, but instead
    access request args directly from the request object, which reduces
    confusion and duplication.
- Handle multiple HTTP response headers with the same name (except for
  Set-Cookie, which is special) by joining the values with a comma space,
  compliant with RFC 7230
- Rewrite cookie support to be much smarter and to use cookie jars consistently
  for requests, responses, and redirection in order to resolve long-standing
  complaints about the previously broken behavior: (#498)
  - The `:cookies` option may now be a Hash of Strings, an Array of
    HTTP::Cookie objects, or a full HTTP::CookieJar.
  - Add `Contractful::Request#cookie_jar` and reimplement `Request#cookies` to
    be a wrapper around the cookie jar.
  - Still support passing the `:cookies` option in the headers hash, but now
    raise ArgumentError if that option is also passed to `Request#initialize`.
  - Warn if both `:cookies` and a `Cookie` header are supplied.
  - Use the `Request#cookie_jar` as the basis for `Response#cookie_jar`,
    creating a copy of the jar and adding any newly received cookies.
  - When following redirection, also use this same strategy so that cookies
    from the original request are carried through in a standards-compliant way
    by the cookie jar.
- Don't set basic auth header if explicit `Authorization` header is specified
- Add `:proxy` option to requests, which can be used for thread-safe
  per-request proxy configuration, overriding `Contractful.proxy`
- Allow overriding `ENV['http_proxy']` to disable proxies by setting
  `Contractful.proxy` to a falsey value. Previously there was no way in Ruby 2.x
  to turn off a proxy specified in the environment without changing `ENV`.
- Add actual support for streaming request payloads. Previously contractful
  would call `.to_s` even on Contractful::Payload::Streamed objects. Instead,
  treat any object that responds to `.read` as a streaming payload and pass it
  through to `.body_stream=` on the Net:HTTP object. This massively reduces the
  memory required for large file uploads.
- Changes to redirection behavior: (#381, #484)
  - Remove `Contractful::MaxRedirectsReached` in favor of the normal
    `ExceptionWithResponse` subclasses. This makes the response accessible on
    the exception object as `.response`, making it possible for callers to tell
    what has actually happened when the redirect limit is reached.
  - When following HTTP redirection, store a list of each previous response on
    the response object as `.history`. This makes it possible to access the
    original response headers and body before the redirection was followed.
  - Follow redirection consistently, regardless of whether the HTTP method was
    passed as a symbol or string. Under the hood contractful now normalizes the
    HTTP request method to a lowercase string.
- Add `:before_execution_proc` option to `Contractful::Request`. This makes it
  possible to add procs like `Contractful.add_before_execution_proc` to a single
  request without global state.
- Run tests on Travis's beta OS X support.
- Make `Request#transmit` a private method, along with a few others.
- Refactor URI parsing to happen earlier, in Request initialization.
- Improve consistency and functionality of complex URL parameter handling:
  - When adding URL params, handle URLs that already contain params.
  - Add new convention for handling URL params containing deeply nested arrays
    and hashes, unify handling of null/empty values, and use the same code for
    GET and POST params. (#437)
  - Add the Contractful::ParamsArray class, a simple array-like container that
    can be used to pass multiple keys with same name or keys where the ordering
    is significant.
- Add a few more exception classes for obscure HTTP status codes.
- Multipart: use a much more robust multipart boundary with greater entropy.
- Make `Contractful::Payload::Base#inspect` stop pretending to be a String.
- Add `Request#redacted_uri` and `Request#redacted_url` to display the URI
  with any password redacted.

# 2.0.0.rc1

Changes in the release candidate that did not persist through the final 2.0.0
release:
- Contractful::Exceptions::Timeout was originally going to be a direct subclass
  of Contractful::Exception in the release candidate. This exception tree was
  made a subclass of Contractful::RequestTimeout prior to the final release.

# 1.8.0

- Security: implement standards compliant cookie handling by adding a
  dependency on http-cookie. This breaks compatibility, but was necessary to
  address a session fixation / cookie disclosure vulnerability.
  (#369 / CVE-2015-1820)

  Previously, any Set-Cookie headers found in an HTTP 30x response would be
  sent to the redirection target, regardless of domain. Responses now expose a
  cookie jar and respect standards compliant domain / path flags in Set-Cookie
  headers.

# 1.7.3

- Security: redact password in URI from logs (#349 / OSVDB-117461)
- Drop monkey patch on MIME::Types (added `type_for_extension` method, use
  the public interface instead.

# 1.7.2

- Ignore duplicate certificates in CA store on Windows

# 1.7.1

- Relax mime-types dependency to continue supporting mime-types 1.x series.
  There seem to be a large number of popular gems that have depended on
  mime-types '~> 1.16' until very recently.
- Improve urlencode performance
- Clean up a number of style points

# 1.7.0

- This release drops support for Ruby 1.8.7 and breaks compatibility in a few
  other relatively minor ways
- Upgrade to mime-types ~> 2.0
- Don't CGI.unescape cookie values sent to the server (issue #89)
- Add support for reading credentials from netrc
- Lots of SSL changes and enhancements: (#268)
  - Enable peer verification by default (setting `VERIFY_PEER` with OpenSSL)
  - By default, use the system default certificate store for SSL verification,
    even on Windows (this uses a separate Windows build that pulls in ffi)
  - Add support for SSL `ca_path`
  - Add support for SSL `cert_store`
  - Add support for SSL `verify_callback` (with some caveats for jruby, OS X, #277)
  - Add support for SSL ciphers, and choose secure ones by default
- Run tests under travis
- Several other bugfixes and test improvements
  - Convert Errno::ETIMEDOUT to Contractful::RequestTimeout
  - Handle more HTTP response codes from recent standards
  - Save raw responses to binary mode tempfile (#110)
  - Disable timeouts with :timeout => nil rather than :timeout => -1
  - Drop all Net::HTTP monkey patches

# 1.6.14

- This release is unchanged from 1.6.9. It was published in order to supersede
  the malicious 1.6.10-13 versions, even for users who are still pinning to the
  legacy 1.6.x series. All users are encouraged to upgrade to rest-client 2.x.

# 1.6.10, 1.6.11, 1.6.12, 1.6.13 (CVE-2019-15224)

- These versions were pushed by a malicious actor and included a backdoor permitting
  remote code execution in Rails environments. (#713)
- They were live for about five days before being yanked.

# 1.6.9

- Move rdoc to a development dependency

# 1.6.8

- The 1.6.x series will be the last to support Ruby 1.8.7
- Pin mime-types to < 2.0 to maintain Ruby 1.8.7 support
- Add Gemfile, AUTHORS, add license to gemspec
- Point homepage at https://github.com/rest-client/rest-client
- Clean up and fix various tests and ruby warnings
- Backport `ssl_verify_callback` functionality from 1.7.0

# 1.6.7

- rebuild with 1.8.7 to avoid https://github.com/rubygems/rubygems/pull/57

# 1.6.6

- 1.6.5 was yanked

# 1.6.5

- RFC6265 requires single SP after ';' for separating parameters pairs in the 'Cookie:' header (patch provided by Hiroshi Nakamura)
- enable url parameters for all actions
- detect file parameters in arrays
- allow disabling the timeouts by passing -1 (patch provided by Sven Böhm)

# 1.6.4

- fix contractful script compatibility with 1.9.2
- fix unlinking temp file (patch provided by Evan Smith)
- monkeypatching ruby for http patch method (patch provided by Syl Turner)

# 1.6.3

- 1.6.2 was yanked

# 1.6.2

- add support for HEAD in resources (patch provided by tpresa)
- fix shell for 1.9.2
- workaround when some gem monkeypatch net/http (patch provided by Ian Warshak)
- DELETE requests should process parameters just like GET and HEAD
- adding :block_response parameter for manual processing
- limit number of redirections (patch provided by Chris Dinn)
- close and unlink the temp file created by playload (patch provided by Chris Green)
- make gemspec Rubygems 1.8 compatible (patch provided by David Backeus)
- added Contractful.reset_before_execution_procs (patch provided by Cloudify)
- added PATCH method (patch provided by Jeff Remer)
- hack for HTTP servers that use raw DEFLATE compression, see http://www.ruby-forum.com/topic/136825 (path provided by James Reeves)

# 1.6.1

- add response body in Exception#inspect
- add support for Contractful.options
- fix tests for 1.9.2 (patch provided by Niko Dittmann)
- block passing in Resource#[] (patch provided by Niko Dittmann)
- cookies set in a response should be kept in a redirect
- HEAD requests should process parameters just like GET (patch provided by Rob Eanes)
- exception message should never be nil (patch provided by Michael Klett)

# 1.6.0

- forgot to include contractful.rb in the gem
- user, password and user-defined headers should survive a redirect
- added all missing status codes
- added parameter passing for get request using the :param key in header
- the warning about the logger when using a string was a bad idea
- multipart parameters names should not be escaped
- remove the cookie escaping introduced by migrating to CGI cookie parsing in 1.5.1
- add a streamed payload type (patch provided by Caleb Land)
- Exception#http_body works even when no response

# 1.5.1

- only converts headers keys which are Symbols
- use CGI for cookie parsing instead of custom code
- unescape user and password before using them (patch provided by Lars Gierth)
- expand ~ in ~/.contractfulrc (patch provided by Mike Fletcher)
- ssl verification raise an exception when the ca certificate is incorrect (patch provided by Braintree)

# 1.5.0

- the response is now a String with the Response module a.k.a. the change in 1.4.0 was a mistake (Response.body is returning self for compatability)
- added AbstractResponse.to_i to improve semantic
- multipart Payloads ignores the name attribute if it's not set (patch provided by Tekin Suleyman)
- correctly takes into account user headers whose keys are strings (path provided by Cyril Rohr)
- use binary mode for payload temp file
- concatenate cookies with ';'
- fixed deeper parameter handling
- do not quote the boundary in the Content-Type header (patch provided by W. Andrew Loe III)

# 1.4.2

- fixed Contractful.add_before_execution_proc (patch provided by Nicholas Wieland)
- fixed error when an exception is raised without a response (patch provided by Caleb Land)

# 1.4.1

- fixed parameters managment when using hash

# 1.4.0

- Response is no more a String, and the mixin is replaced by an abstract_response, existing calls are redirected to response body with a warning.
- enable repeated parameters  Contractful.post 'http://example.com/resource', :param1 => ['one', 'two', 'three'], => :param2 => 'foo' (patch provided by Rodrigo Panachi)
- fixed the redirect code concerning relative path and query string combination (patch provided by Kevin Read)
- redirection code moved to Response so redirection can be customized using the block syntax
- only get and head redirections are now followed by default, as stated in the specification
- added Contractful.add_before_execution_proc to hack the http request, like for oauth

The response change may be breaking in rare cases.

# 1.3.1

- added compatibility to enable responses in exception to act like Net::HTTPResponse

# 1.3.0

- a block can be used to process a request's result, this enable to handle custom error codes or paththrought (design by Cyril Rohr)
- cleaner log API, add a warning for some cases but should be compatible
- accept multiple "Set-Cookie" headers, see http://www.ietf.org/rfc/rfc2109.txt (patch provided by Cyril Rohr)
- remove "Content-Length" and "Content-Type" headers when following a redirection (patch provided by haarts)
- all http error codes have now a corresponding exception class and all of them contain the Reponse -> this means that the raised exception can be different
- changed "Content-Disposition: multipart/form-data" to "Content-Disposition: form-data" per RFC 2388 (patch provided by Kyle Crawford)

The only breaking change should be the exception classes, but as the new classes inherits from the existing ones, the breaking cases should be rare.

# 1.2.0

- formatting changed from tabs to spaces
- logged requests now include generated headers
- accept and content-type headers can now be specified using extentions: Contractful.post "http://example.com/resource", { 'x' => 1 }.to_json, :content_type => :json, :accept => :json
- should be 1.1.1 but renamed to 1.2.0 because 1.1.X versions has already been packaged on Debian

# 1.1.0

- new maintainer: Archiloque, the working repo is now at http://github.com/archiloque/contractful
- a mailing list has been created at rest.client@librelist.com and an freenode irc channel #rest-client
- François Beausoleil' multipart code from http://github.com/francois/contractful has been merged
- ability to use hash in hash as payload
- the mime-type code now rely on the mime-types gem http://mime-types.rubyforge.org/ instead of an internal partial list
- 204 response returns a Response instead of nil (patch provided by Elliott Draper)

All changes exept the last one should be fully compatible with the previous version.

NOTE: due to a dependency problem and to the last change, heroku users should update their heroku gem to >= 1.5.3 to be able to use this version.
