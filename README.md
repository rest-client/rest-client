# Contractful — a contract-first HTTP client for Ruby

[![Gem Downloads](https://img.shields.io/gem/dt/contractful.svg)](https://rubygems.org/gems/contractful)
[![CI](https://github.com/shubhamtaywade82/contractful/actions/workflows/ci.yml/badge.svg)](https://github.com/shubhamtaywade82/contractful/actions/workflows/ci.yml)

Contractful is a Ruby HTTP client whose behavior is driven by **contracts**:
closed request schemas that reject bad input before the network is touched,
open response schemas that treat unknown fields as data, and contract-level
auth, idempotency, pagination, rate limits and error classification. Client
classes are generated from contract definitions via metaprogramming, an
OpenAPI import helper turns existing specs into contracts, and a
recorded-sequence helper replays captured vendor interactions in tests.

* Main page: https://github.com/shubhamtaywade82/contractful

### Heritage

This project began as a modernization of the original
[rest-client](https://github.com/rest-client/rest-client) gem, which was
archived by its maintainers in 2019 and had fallen behind modern Ruby
releases. That modernization kept the gem alive on Ruby 3.0 through 4.0,
moved to current development tooling, and added long-requested options such
as `:write_timeout` and `:ssl_min_version` / `:ssl_max_version`. The
codebase then evolved into a contract-first client, and at version 0.1.0 it
was renamed **contractful** — the `rest-client` name on RubyGems belongs to
the original project, and no version of this codebase was ever published
under it. The MIT license and the upstream copyright are preserved in
[LICENSE](LICENSE); comments that cite upstream issues link to the original
repository on purpose. See [history.md](history.md) for the full list of
changes.

### Project documentation

The complete engineering documentation set lives at the root and under
`docs/`:

| Document | Purpose |
| --- | --- |
| [PRD.md](PRD.md) | Product goals, non-goals, feature requirements |
| [DESIGN.md](DESIGN.md) | Developer-experience and interface design principles |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Layers, module map, request lifecycle |
| [API.md](API.md) | Normative public API reference (incl. the contract DSL) |
| [DATABASE.md](DATABASE.md) | No-database decision, in-memory state, fixture policy |
| [AGENTS.md](AGENTS.md) | Rules for AI coding agents working in this repo |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Human contributor workflow |
| [SECURITY.md](SECURITY.md) | Vulnerability reporting and disclosure policy |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | Contributor Covenant (2.1) |
| [docs/guides/raw-http-deep-dive.md](docs/guides/raw-http-deep-dive.md) | ActiveResource facade, redirect chains, result-handling styles, streaming, shell, hooks |
| [docs/requirements/REQUIREMENTS.md](docs/requirements/REQUIREMENTS.md) | Traceability: requirements ↔ specs ↔ status |
| [docs/implementation/IMPLEMENTATION_PLAN.md](docs/implementation/IMPLEMENTATION_PLAN.md) | Roadmap workstreams and sequencing |
| [docs/implementation/SETUP.md](docs/implementation/SETUP.md) | Tested local development setup |
| [docs/engineering/TESTING.md](docs/engineering/TESTING.md) | Test strategy, organization, known traps |
| [docs/engineering/QUALITY_GATES.md](docs/engineering/QUALITY_GATES.md) | Merge/release gates and enforcement |
| [docs/engineering/ERROR_HANDLING.md](docs/engineering/ERROR_HANDLING.md) | Exception model, retryable vs terminal |
| [docs/engineering/INTEGRATIONS.md](docs/engineering/INTEGRATIONS.md) | Dependencies, platforms, downstream consumers |
| [docs/security/THREAT_MODEL.md](docs/security/THREAT_MODEL.md) | Assets, trust boundaries, mitigations |
| [docs/security/AGENT_TOOL_POLICY.md](docs/security/AGENT_TOOL_POLICY.md) | Permission boundaries for autonomous agents |
| [docs/operations/DELIVERY.md](docs/operations/DELIVERY.md) | Versioning, releases, rollback |
| [docs/operations/OBSERVABILITY.md](docs/operations/OBSERVABILITY.md) | Logging, diagnostics, health signals |
| [docs/operations/RUNBOOK.md](docs/operations/RUNBOOK.md) | Symptom → diagnosis → fix field guide |
| [docs/adr/](docs/adr/) | Architecture decision records (0001–0003) |
| [docs/agents/AGENT_WORKFLOWS.md](docs/agents/AGENT_WORKFLOWS.md) | Phase-by-phase agent execution playbook |
| [docs/agents/MCP_INTEGRATION.md](docs/agents/MCP_INTEGRATION.md) | MCP policy (conditional document) |

## Requirements

MRI Ruby 3.0 and newer are supported, including Ruby 4.0. The full test suite
runs in CI against Ruby 3.0, 3.1, 3.2, 3.3, 3.4, and 4.0 (plus ruby-head on a
best-effort basis). Alternative interpreters compatible with Ruby 3.0+ such as
JRuby should work as well.

Ruby 2.x versions are no longer supported. Ruby 3.0, 3.1, and 3.2 have reached
end-of-life upstream; they are still covered by this gem's test matrix, but
users are encouraged to run a maintained Ruby release.

The contractful gem depends on these other gems for usage at runtime:

* [mime-types](http://rubygems.org/gems/mime-types)
* [netrc](http://rubygems.org/gems/netrc)
* [http-accept](https://rubygems.org/gems/http-accept)
* [http-cookie](https://rubygems.org/gems/http-cookie)

There are also several development dependencies. It's recommended to use
[bundler](http://bundler.io/) to manage these dependencies for hacking on
contractful.

### Upgrading from rest-client

contractful 0.1.0 is the renamed continuation of the modernized rest-client
codebase. Update the gem name, the `require` path, and the `RestClient`
constants to `contractful` / `Contractful`; the request API and options are
otherwise unchanged.

The rest-client 2.0 line, included in this codebase, cleaned up a number of
API warts and wrinkles. Usage is largely compatible, so many applications will
be able to upgrade with no changes.

Overview of significant changes:

* requires Ruby >= 3.0
* `Contractful::Response` objects are a subclass of `String` rather than a
  Frankenstein monster. And `#body` or `#to_s` return a true `String` object.
* cleanup of exception classes, including new `Contractful::Exceptions::Timeout`
* improvements to handling of redirects: responses and history are properly
  exposed
* major changes to cookie support: cookie jars are used for browser-like
  behavior throughout
* encoding: Content-Type charset response headers are used to automatically set
  the encoding of the response string
* HTTP params: handling of GET/POST params is more consistent and sophisticated
  for deeply nested hash objects, and `ParamsArray` can be used to pass ordered
  params
* improved proxy support with per-request proxy configuration, plus the ability
  to disable proxies set by environment variables
* default request headers: contractful sets `Accept: */*` and
  `User-Agent: contractful/...`

See [history.md](./history.md) for a more complete description of changes.

## Usage: Raw URL

Basic usage:

```ruby
require 'contractful'

Contractful.get(url, headers={})

Contractful.post(url, payload, headers={})
```

In the high level helpers, only POST, PATCH, and PUT take a payload argument.
To pass a payload with other HTTP verbs or to pass more advanced options, use
`Contractful::Request.execute` instead.

More detailed examples:

```ruby
require 'contractful'

Contractful.get 'http://example.com/resource'

Contractful.get 'http://example.com/resource', {params: {id: 50, 'foo' => 'bar'}}

Contractful.get 'https://user:password@example.com/private/resource', {accept: :json}

Contractful.post 'http://example.com/resource', {param1: 'one', nested: {param2: 'two'}}

Contractful.post "http://example.com/resource", {'x' => 1}.to_json, {content_type: :json, accept: :json}

Contractful.delete 'http://example.com/resource'

>> response = Contractful.get 'http://example.com/resource'
=> <Contractful::Response 200 "<!doctype h...">
>> response.code
=> 200
>> response.cookies
=> {"Foo"=>"BAR", "QUUX"=>"QUUUUX"}
>> response.headers
=> {:content_type=>"text/html; charset=utf-8", :cache_control=>"private" ... }
>> response.body
=> "<!doctype html>\n<html>\n<head>\n    <title>Example Domain</title>\n\n ..."

Contractful.post( url,
  {
    :transfer => {
      :path => '/foo/bar',
      :owner => 'that_guy',
      :group => 'those_guys'
    },
     :upload => {
      :file => File.new(path, 'rb')
    }
  })
```
## Passing advanced options

The top level helper methods like Contractful.get accept a headers hash as
their last argument and don't allow passing more complex options. But these
helpers are just thin wrappers around `Contractful::Request.execute`.

```ruby
Contractful::Request.execute(method: :get, url: 'http://example.com/resource',
                            timeout: 10)

Contractful::Request.execute(method: :get, url: 'http://example.com/resource',
                            ssl_ca_file: 'myca.pem',
                            ssl_ciphers: 'AESGCM:!aNULL')
```
You can also use this to pass a payload for HTTP verbs like DELETE, where the
`Contractful.delete` helper doesn't accept a payload.

```ruby
Contractful::Request.execute(method: :delete, url: 'http://example.com/resource',
                            payload: 'foo', headers: {myheader: 'bar'})
```

Due to unfortunate choices in the original API, the params used to populate the
query string are actually taken out of the headers hash. So if you want to pass
both the params hash and more complex options, use the special key
`:params` in the headers hash. This design may change in a future major
release.

```ruby
Contractful::Request.execute(method: :get, url: 'http://example.com/resource',
                            timeout: 10, headers: {params: {foo: 'bar'}})

➔ GET http://example.com/resource?foo=bar
```

## Automatic retries

Requests can be retried automatically when they fail with a
transient network-level error. Opt in with `:max_retries`; delays between
attempts grow exponentially from `:retry_interval` (default 0.5s):
`retry_interval`, `retry_interval * 2`, `retry_interval * 4`, ...

```ruby
Contractful::Request.execute(method: :get, url: 'http://example.com/resource',
                            max_retries: 3, retry_interval: 0.5)
```

Retried failures are network errors: open/read/write timeouts, a server
that breaks the connection (`EOFError`), connection reset/abort, and broken
pipes. By default HTTP error responses (4xx/5xx) are never retried — see
the retryable-status classification below for the exception — and
redirects behave as usual.

The error model classifies failures as **retryable
vs terminal**. HTTP statuses 408, 425, 429, 500, 502, 503 and 504
(`Contractful::Exceptions::RETRIABLE_STATUSES`) are treated as transient like
network failures and retried when `:max_retries` is positive. Between
attempts the server's `Retry-After` header is honored (delta-seconds or
HTTP-date, capped by `:max_retry_after`, default 60) instead of blind
backoff. Opt out entirely with `retry_after: false`. The classification is
exposed for your own retry logic too:

```ruby
Contractful::Exceptions.retryable?(429)                        # => true
Contractful::Exceptions.retryable?(404)                        # => false
Contractful::Exceptions.retryable?(ex)   # exception or network error
Contractful::ServiceUnavailable.new(response).retryable?       # => true
```

Every other 4xx (401, 404, 422, ...) is terminal: retrying will not fix a
bad token, a missing resource or a bad payload. Retryable-status retries
also apply inside the block/error-suppression path, so contract clients get
them via `_max_retries:` as well.

Request payloads are rewound between attempts, so bodies are retransmitted in
full. If a payload cannot be rewound (for example a non-seekable request
stream), the request is not retried and the original network error is raised.

```ruby
# 1st attempt times out, retries after 0.5s, 2nd attempt succeeds
Contractful::Request.execute(method: :get, url: 'http://example.com',
                            max_retries: 2, open_timeout: 2)
```

Retrying in lockstep is its own outage amplifier:
when many clients hit the same failing service, identical exponential
backoff makes them all knock again at the same instant. `:retry_jitter`
randomizes the computed backoff so retries spread out — `:full` draws from
`[0, backoff]`, `:equal` from `[backoff, 2 * backoff]`, and `:decorrelated`
follows the AWS "Exponential Backoff and Jitter" recipe (`:full` is what it
recommends for most systems). Jitter applies only to the computed backoff:
a server's `Retry-After` is still honored exactly as sent. A seeded
`:retry_rng` (any object answering `#rand(range)`) makes tests
deterministic.

```ruby
Contractful::Request.execute(method: :get, url: 'http://example.com',
                            max_retries: 3, retry_jitter: :full)
```

## Persistent connections (keep-alive)

Pass `persistent: true` to reuse the underlying TCP/TLS
connection across requests via the process-wide connection pool, instead of
opening a new connection for every request. This saves the connection and TLS
handshake overhead when making many requests to the same host.

```ruby
Contractful::Request.execute(method: :get, url: 'https://api.example.com/things',
                            persistent: true)

Contractful::Request.execute(method: :post, url: 'https://api.example.com/things',
                            payload: ..., persistent: true)

Contractful.connection_pool.stats   # => {idle: 1, checked_out: 0}
Contractful.connection_pool.clear!  # close all pooled connections
```

How it behaves:

- Connections are pooled per scheme/host/port plus proxy and SSL settings.
  Requests to different hosts (or through different proxies) get their own
  pooled connections, and redirects automatically use the pool for the target
  host.
- A connection is never shared between concurrent requests; if no idle
  connection is available, a new one is opened (just like a non-persistent
  request). At most a few idle connections per host are retained
  (`Contractful::ConnectionPool.new(max_idle: 8)` by default).
- After a network failure the connection is discarded rather than reused;
  HTTP error responses (4xx/5xx) do not affect the connection.
- Stale connections closed by the server are detected and re-established on
  the next use.

Call `Contractful.connection_pool.clear!` before forking a process or when you
know connections have gone stale.

## Circuit breaker

Retries answer transient errors; a circuit breaker
answers a host that is *down* — without one, every request still pays the
full timeout and every retry amplifies the load on something that is
already dying. Opt in per request with `breaker: true` (defaults) or a
config Hash:

```ruby
Contractful::Request.execute(method: :get, url: 'https://api.example.com/x',
                            breaker: { threshold: 5, cooldown: 30 })
```

Counted as failures: network errors and retryable statuses (408/425/429/5xx)
from requests whose retries are exhausted; client errors like 404 never
open a circuit. After `threshold` consecutive failures every request to
that scheme/host/port fails fast with `Contractful::CircuitOpenError` for
`cooldown` seconds; the next request after the cooldown probes the host
(half-open) and its outcome closes or re-opens the circuit. Breakers are
process-wide and thread-safe; state transitions post a `circuit`
notification (see [Event notifications](#event-notifications)), so metrics
can watch open/half-open/closed as a first-class signal. The first breaker
configuration for a scheme/host/port wins; later `breaker:` values for the
same origin reuse the existing breaker.

```ruby
Contractful::Notifications.subscribe do |event|
  next unless event[:name] == 'circuit'
  puts "circuit #{event[:payload][:key]}: #{event[:payload][:from]} -> #{event[:payload][:state]}"
end
```

## Rate-limit pacing

The breaker reacts to failure; pacing prevents the 429s in the first place.
Opt in per request with `pace: true` (defaults: 600 requests per 60s window)
or a config Hash:

```ruby
Contractful::Request.execute(method: :get, url: 'https://api.example.com/x',
                            pace: { limit: 100, window: 60, max_wait: 10 })
```

Pacing is per scheme/host/port across the whole process (all threads
included) using a sliding window: every attempt — retries included —
acquires a slot before the request leaves. The first `pace:` configuration
for an origin wins; later values reuse the existing pacer. A full window
makes the request sleep until the oldest slot expires (posting a `pace`
notification with the delay); a wait longer than `max_wait` raises
`Contractful::PacingTimeout` instead of stalling silently. Callers that
cannot tolerate waiting should set a small `max_wait` and treat the
timeout as their own backpressure signal.

## Contract-first API clients

`Contractful::Contract` is a contract-first layer built on
heavy metaprogramming: you *declare* the HTTP shape of an API — verb, path,
typed parameters, expected responses — and the gem generates the client
methods, path builders, validation and introspection for you. The contract
*is* the implementation; there is no imperative request code to write or
drift.

```ruby
class GitHubAPI
  include Contractful::Contract

  base 'https://api.github.com'
  default_headers 'Accept' => 'application/vnd.github+json'

  before_request do |ctx|
    ctx[:headers]['Authorization'] = "token #{ENV['GITHUB_TOKEN']}"
  end

  contract :list_users, 'GET /users' do
    param :page,     Integer, default: 1
    param :per_page, Integer, inclusion: (1..100), default: 30
    responds 200, type: :array
  end

  contract :create_issue, 'POST /repos/:owner/:repo/issues' do
    param :owner, String, required: true
    param :repo,  String, required: true
    param :title, String, required: true
    param :labels, Array, default: []
    responds 201, 422
  end
end

api = GitHubAPI.new
api.list_users(page: 2)
api.create_issue(owner: 'octo', repo: 'hello', title: 'Hi', labels: ['bug'])
api.create_issue_url(owner: 'octo', repo: 'hello') # => "https://api.github.com/repos/octo/hello/issues"
```

### Typed parameters

Every value passed to a contract method is coerced and validated before any
HTTP traffic happens. Supported types: `String`, `Integer`, `Float`,
`:boolean`, `Array`, `Hash`, any class (checked with `is_a?`, then
`Class#contractful_coerce` if defined, then a Kernel cast) and any `Proc`
(its return value is used). Options: `required:`, `default:` (lazy procs
allowed), `inclusion:` and `coerce: false` for strict type checking.

```ruby
contract :search, 'GET /search' do
  param :q,        String,  required: true
  param :page,     Integer, default: 1
  param :per_page, Integer, inclusion: (1..100), default: 25
  param :sort,     String,  inclusion: %w[asc desc], default: 'desc'
end
```

Params also carry the closed-schema constraints known from JSON Schema /
OpenAPI: `min:` / `max:` (inclusive bounds on any Comparable), `length:`
(exact Integer or a Range, over String/Array/Hash) and `pattern:` (Regexp on
Strings). Constraints are enforced after coercion, so a `min: 1` Integer
param rejects the string `"0"` exactly like the integer 0:

```ruby
contract :create_order, 'POST /orders' do
  param :security_id,      String,  required: true, length: (1..20)
  param :transaction_type, String,  required: true, inclusion: %w[BUY SELL]
  param :quantity,         Integer, required: true, min: 1
end
```

Violations raise a precise error instead of producing a malformed request:

- `Contractful::Contract::MissingParam` — required param absent
- `Contractful::Contract::UnknownParam` — undeclared param in strict mode
- `Contractful::Contract::InvalidParam` — value failed coercion/validation

Unknown params are rejected by default (contract-first strictness); opt out
per class with `strict_params false` or per contract with `strict_params
false` inside the block. Remaining (declared) params are routed by verb:
query string for GET/HEAD/DELETE/OPTIONS, JSON body (`Content-Type:
application/json`) for POST/PUT/PATCH. Override with `payload_style :form`
or `:query` per contract, or `payload_style :form` at class level.

Path placeholders (`:owner`, `:repo`) are automatically declared as required
params, interpolated into the path, URI-escaped, and never duplicated into
the query string or payload.

### Per-call meta options

Underscore-prefixed keyword arguments configure the underlying request
without polluting the param contract: `_headers`, `_timeout`,
`_open_timeout`, `_read_timeout`, `_write_timeout`, `_persistent`,
`_max_retries`, `_retry_interval`.

```ruby
api.list_users(_headers: { 'X-Request-Id' => SecureRandom.hex(8) },
               _timeout: 5, _persistent: true)
```

### Response contracts

`responds` declares what an operation expects back: status codes (Integers or
Ranges) and an optional JSON body type (`Array`, `Hash`, `String`, any class,
or `:array`/`:hash`/`:string`/`:json`).

```ruby
contract :show_widget, 'GET /widgets/:id' do
  param :id, Integer
  responds 200, 404          # 404 becomes a normal return value
end

contract :list_posts, 'GET /posts' do
  responds (200..299), type: Array
  verify_response { |_response, parsed| parsed.is_a?(Array) }
end
```

Declaring any 4xx/5xx status suppresses contractful's default
exception-raising for that contract: the response is returned and judged by
the contract instead (redirects are still followed). Anything unexpected —
undeclared status, non-JSON body, wrong shape, failed `verify_response`
block — raises `Contractful::Contract::UnexpectedResponse` with the offending
`response` attached. Contracts without any response declaration keep the
classic contractful behavior (`ResourceNotFound`, etc.).

### Closed requests, open responses

The request and response halves of a contract follow different philosophies,
and the DSL encodes both:

- **Request schemas are closed.** You control what you send, so reject bad
  input before the network call: undeclared params raise `UnknownParam`, and
  declared params are type-checked, enum-checked and range-checked
  (`inclusion:`, `min:`/`max:`, `length:`, `pattern:`) before the transport
  is ever touched.
- **Response schemas are open.** Required fields and their types bind, but
  new fields and new enum members are additive — unknown values are data,
  not errors. Declare response fields with `response_field`:

```ruby
contract :create_order, 'POST /orders' do
  param :security_id, String, required: true
  param :quantity,    Integer, required: true, min: 1

  response_field :order_id, :string, required: true
  response_field :status,   :string   # open: new states are additive
end
```

A required field that is missing or null, or a declared field whose value
does not match its type (an `orderId` that comes back as an integer, for
example), raises `UnexpectedResponse` on return. Undeclared fields pass
through untouched and are never errors; `inclusion:` on a response field is
not enforced unless you opt in with `strict: true`. Values are never
coerced — what the server sent is what you inspect.

One thing a contract cannot express is ordering, timing or cross-call state
machines (rate-limit windows, order lifecycles, pagination handshakes).
Test those separately against recorded sequences rather than trying to
encode them in the per-call contract.

### Auth in the contract

The contract is the source of truth for *how* to authenticate; the client
supplies only credentials. Values may be literals or callables — callables
are invoked on every request so short-lived tokens stay fresh. Multiple
`api_key` entries cover dual-header schemes (DhanHQ's `access-token` +
`client-id`, for example):

```ruby
class DhanHQClient
  include Contractful::Contract

  base 'https://api.dhan.co'
  auth api_key: [
    { name: 'access-token', value: -> { ENV['DHAN_ACCESS_TOKEN'] } },
    { name: 'client-id',    value: -> { ENV['DHAN_CLIENT_ID'] } },
  ]
  # also available: auth bearer: -> { token }, auth basic: -> { [user, pass] }
  # and auth api_key: { name: 'k', value: v, in: :query }
end
```

For OAuth-style flows with short-lived tokens, give the contract a
**token provider** — an object that answers `#token` (the current
credential) and `#refresh` (force a new one). The client class stays
credential-free, and a 401 is handled for you:

```ruby
class TokenStore
  def token      = @token
  def refresh
    @token = fetch_new_token   # your OAuth2 client-credentials flow
  end
end

class DhanHQClient
  include Contractful::Contract
  base 'https://api.dhan.co'
  auth token_provider: TokenStore.new
end
```

When a request comes back 401, the executor refreshes the provider in
**one flight** (concurrent 401s share a single refresh — per-provider
mutex, posting a `token_refresh` notification) and retries the request
exactly once with the fresh credential. A second 401 is returned or
raised like any other declared status; there is no refresh loop.

Auth is resolved right before the `before_request` callbacks run, so
callbacks can still inspect or override the resolved credentials. Individual
contracts can opt out with `auth false` inside the block. Auth config
inherits down the class chain, nearest definition wins.

### Idempotency keys

Flag a contract `idempotent` and every call carries an idempotency key
header (default `Idempotency-Key`, generated with `SecureRandom.uuid`),
which makes automatic retries of non-GET operations safe. The key is
generated once per logical call and stays stable across retries — that is
the entire point of the header. Customize the header name with
`idempotency_header` and the generator with `idempotency_generator` at
class level; pin a specific key per call with `_idempotency_key:`.

```ruby
contract :create_order, 'POST /orders' do
  param :security_id, String, required: true
  idempotent true
end

api.create_order(security_id: 'X1', _max_retries: 2)
# a 503 will be retried with the SAME Idempotency-Key
```

### Pagination

Collection contracts can declare their pagination strategy; the pagination
params must also be declared as regular contract params. Every paginated
contract gets two metaprogrammed methods: `#{name}_pages` (a lazy Enumerator
of per-page responses, each fully validated by the contract) and
`all_#{name}` (a flat Array of every item across pages).

```ruby
contract :list_orders, 'GET /orders' do
  param :pageToken, String
  param :pageSize,  Integer, default: 50

  paginated style: :cursor, cursor_param: :pageToken,
            next_cursor_path: 'nextPageToken', items_path: 'orders'
end

api.list_orders_pages.take(3)     # first three validated pages
api.all_list_orders               # every order across every page
```

Offset pagination is covered too: `paginated style: :offset,
offset_param: :offset, limit_param: :limit, items_path: 'data',
has_more_path: 'hasMore'` — iteration stops when `has_more_path` is false
or (without it) when a page comes back empty. A `_max_pages` guard (default
1000) turns a missing stop condition into
`Contractful::Contract::PaginationError` instead of an infinite request
loop, and page 1 can resume from an explicitly supplied cursor or offset.

### Rate-limit information

Every response exposes parsed quota state when the server sends the IETF
`RateLimit-*` headers or the legacy `X-RateLimit-*` convention (servers that
document limits only in prose — DhanHQ, for instance — simply yield `nil`;
data absence is not an error):

```ruby
response = api.list_orders
response.rate_limit&.remaining   # => 98
response.rate_limit&.reset_in    # => 12.4 (seconds)
response.rate_limited?           # => true on a 429 or an exhausted quota
```

A 429 that carries no `Retry-After` falls back to the `RateLimit-Reset`
window before resorting to exponential backoff.

### Callbacks

`before_request` receives a *mutable* context
(`definition:, method:, url:, headers:, payload:, query:`) — mutating it
changes the outgoing request, which is ideal for auth injection.
`after_response` receives the validated response. Both accumulate down the
inheritance chain, root-most first, so a base client class can hold shared
middleware.

### Generated CRUD resources

`resource :posts` metaprograms the five standard REST contracts —
`list_posts`, `get_post(id)`, `create_post(attrs)`, `update_post(id, attrs)`,
`delete_post(id)` — with `only:`/`except:` filters, `update_with: :put`,
`path:` override and a small English singularizer (override with
`singular:`). Generated CRUD contracts accept free-form attributes
(non-strict); declare contracts by hand when you want strict validation.

```ruby
class BlogAPI
  include Contractful::Contract
  base 'https://api.example.com'
  resource :posts, only: %i[index show create]
end

BlogAPI.new.create_post(title: 'Hello', body: '...')  # POST /posts
```

### Reflection and dynamic dispatch

Everything registered through the DSL is introspectable:

```ruby
GitHubAPI.contract_names          # => [:list_users, :create_issue]
GitHubAPI.contract?(:list_users)  # => true
GitHubAPI.contract_for(:list_users)  # => #<Contractful::Contract::Definition GET /users ...>
GitHubAPI.contract_for(:list_users).describe
# => "GET /users (params: :page, :per_page) responds 200 => Array"

api.list_users_contract  # the Definition (dynamic dispatch)
api.call_list_users(page: 1)  # execute by name
api.has_list_users?  # => true
```

Clients also accept instance-level overrides: `GitHubAPI.new(base:
'https://staging.example.com', headers: { 'X-Env' => 'test' })`.

### Importing an OpenAPI document

If a vendor publishes a machine-readable OpenAPI 3.x document, the opt-in
import helper converts it into `contract` declarations — a development-time
tool, not a runtime dependency (it is not loaded by `require 'contractful'`):

```ruby
require 'contractful/contract/openapi_import'

# Build Definition objects from a file, YAML/JSON text or a Hash:
import = Contractful::Contract::OpenAPIImport.import('vendor_openapi.yaml')
import.definitions   # => { list_users: #<Definition GET /users ...>, ... }
import.base_url      # from `servers`
import.notes         # every lossy mapping decision, for review

# Or render a ready-to-paste client class:
puts Contractful::Contract::OpenAPIImport.to_ruby('vendor_openapi.yaml',
                                                 class_name: 'Acme::Client')
```

What is mapped: path/query/body-object params (types, required, defaults,
enum/min/max/length/pattern constraints), `payload_style` (form for
urlencoded bodies, query for body-less POST/PUT/PATCH), response statuses
(numeric and `2XX` wildcards), JSON body types and open-schema
`response_field` bindings, the base URL from `servers`, and auth hints from
`securitySchemes` (as comments — credentials are never invented).

What is NOT mapped is reported on `import.notes` instead of guessed away:
header/cookie params, multipart bodies, `oneOf`/`anyOf` unions, `default`
responses, operation-level server overrides. The generated source
round-trips: evaluating it yields a class whose contracts `describe`
exactly like the imported definitions.

### Testing sequences with recorded fixtures

Contracts deliberately do not express ordering, timing or cross-call state
machines. The opt-in sequence helper replays recorded vendor responses
through a contract client and fails on the FIRST contract violation with
the step number attached (test-only — it uses WebMock):

```ruby
require 'contractful/contract/sequence'

sequence = Contractful::Contract::Sequence.load(client, 'order_lifecycle.yml')
sequence.after_step do |index, step, response|
  # stateful rules contracts cannot express: token refresh sequencing,
  # rate-limit windows (response.rate_limit), cross-step invariants
end
sequence.run   # => [#<Result step 1>, ...] or raises Sequence::Failure
```

Fixture shape (YAML or JSON, under your control):

```yaml
name: order lifecycle
steps:
  - call: create_order
    params: { quantity: 10 }
    response: { status: 201, body: { order_id: 'o-1', status: 'open' } }
    expect_request:
      json_include: { quantity: 10 }     # assert the OUTGOING payload subset
  - call: get_order
    params: { order_id: 'o-1' }
    response: { status: 200, body: { order_id: 'o-1', status: 'filled' } }
    expect_request:
      path: /orders/o-1
```

Each step stubs its recorded response, invokes the contract method and
lets the contract's own validation run — a recorded response the contract
does not declare is a violation at that step. `expect_request` pins
ordering-sensitive outgoing details (`path`, `query_include`,
`headers_include`, `json_include` — unknown keys fail the fixture loudly).
Unknown contract names, malformed steps and missing responses are rejected
at load time, before anything runs.

## Event notifications

The request pipeline posts lifecycle events to an
in-process hub, so metrics, tracing and alerting never require touching the
transport. Subscribers must not raise — a failing subscriber is logged and
skipped, so observability cannot break the request it observes:

```ruby
Contractful::Notifications.subscribe do |event|
  puts "#{event[:name]} #{event[:payload].inspect}"
end
# request  {method: 'get', url: 'https://api.test/x', attempt: 1}
# response {method: 'get', url: 'https://api.test/x', status: 200, duration_ms: 43.12}
# retry    {method: 'get', url: 'https://api.test/x', attempt: 1, delay: 0.5, cause: 503}
```

The core posts `request` (method, url, attempt), `response` (status,
duration_ms — one per attempt, including suppressed error responses) and
`retry` (attempt, delay, cause — an exception class name or HTTP status).
Resilience features add their own events (circuit breaker state changes,
rate-limit sleeps, token refreshes). `subscribe` returns an unsubscribe
handle; `Notifications.clear!` detaches everything (test hook).

For Rails and APM integration, an opt-in bridge forwards every event to
ActiveSupport::Notifications as `contractful.<name>`:

```ruby
require 'contractful/notifications/active_support'   # requires the activesupport gem

ActiveSupport::Notifications.subscribe(/^contractful\./) do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Rails.logger.info "#{event.name} in #{event.duration}ms #{event.payload.slice(:url, :status)}"
end
```

## Multipart

Yeah, that's right!  This does multipart sends for you!

```ruby
Contractful.post '/data', :myfile => File.new("/path/to/image.jpg", 'rb')
```

This does two things for you:

- Auto-detects that you have a File value sends it as multipart
- Auto-detects the mime of the file and sets it in the HEAD of the payload for each entry

If you are sending params that do not contain a File object but the payload needs to be multipart then:

```ruby
Contractful.post '/data', {:foo => 'bar', :multipart => true}
```

## Exceptions (see http://www.w3.org/Protocols/rfc2616/rfc2616-sec10.html)

- for result codes between `200` and `207`, a `Contractful::Response` will be returned
- for result codes `301`, `302` or `307`, the redirection will be followed if the request is a `GET` or a `HEAD`
- for result code `303`, the redirection will be followed and the request transformed into a `GET`
- for other cases, a `Contractful::ExceptionWithResponse` holding the Response will be raised; a specific exception class will be thrown for known error codes
- call `.response` on the exception to get the server's response

```ruby
>> Contractful.get 'http://example.com/nonexistent'
Exception: Contractful::NotFound: 404 Not Found

>> begin
     Contractful.get 'http://example.com/nonexistent'
   rescue Contractful::ExceptionWithResponse => e
     e.response
   end
=> <Contractful::Response 404 "<!doctype h...">
```

### Other exceptions

While most exceptions have been collected under `Contractful::RequestFailed` aka
`Contractful::ExceptionWithResponse`, there are a few quirky exceptions that
have been kept for backwards compatibility.

Contractful will propagate up exceptions like socket errors without modification:

```ruby
>> Contractful.get 'http://localhost:12345'
Exception: Errno::ECONNREFUSED: Connection refused - connect(2) for "localhost" port 12345
```

Contractful handles a few specific error cases separately in order to give
better error messages. These will hopefully be cleaned up in a future major
release.

`Contractful::ServerBrokeConnection` is translated from `EOFError` to give a
better error message.

`Contractful::SSLCertificateNotVerified` is raised when HTTPS validation fails.
Other `OpenSSL::SSL::SSLError` errors are raised as is.

## Lower-level access

> Redirect-chain mechanics (`response.history`, per-request URLs), the
> block/exception result-handling styles and the ActiveResource-style
> facade are documented in the
> [raw HTTP deep dive](docs/guides/raw-http-deep-dive.md).

For cases not covered by the general API, you can use the `Contractful::Request` class, which provides a lower-level API.

You can:

- specify ssl parameters
- override cookies
- manually handle the response — streaming request payloads and streamed
  response downloads live in the
  [raw HTTP deep dive](docs/guides/raw-http-deep-dive.md#streaming-request-payload)

See `Contractful::Request`'s documentation for more information.

## Logging

To enable logging globally you can:

- set Contractful.log with a Ruby Logger

```ruby
Contractful.log = STDOUT
```

- or set an environment variable to avoid modifying the code (in this case you can use a file name, "stdout" or "stderr"):

```ruby
$ CONTRACTFUL_LOG=stdout path/to/my/program
```

You can also set individual loggers when instantiating a Resource or making an
individual request:

```ruby
resource = Contractful::Resource.new 'http://example.com/resource', log: Logger.new(STDOUT)
```

```ruby
Contractful::Request.execute(method: :get, url: 'http://example.com/foo', log: Logger.new(STDERR))
```

All options produce logs like this:

```ruby
Contractful.get "http://some/resource"
# => 200 OK | text/html 250 bytes
Contractful.put "http://some/resource", "payload"
# => 401 Unauthorized | application/xml 340 bytes
```

Note that these logs are valid Ruby, so you can paste them into the `contractful`
shell or a script to replay your sequence of rest calls.

## Proxy

All calls to Contractful, including Resources, will use the proxy specified by
`Contractful.proxy`:

```ruby
Contractful.proxy = "http://proxy.example.com/"
Contractful.get "http://some/resource"
# => response from some/resource as proxied through proxy.example.com
```

Often the proxy URL is set in an environment variable, so you can do this to
use whatever proxy the system is configured to use:

```ruby
  Contractful.proxy = ENV['http_proxy']
```

Specify a per-request proxy by passing the :proxy option to
Contractful::Request. This will override any proxies set by environment variable
or by the global `Contractful.proxy` value.

```ruby
Contractful::Request.execute(method: :get, url: 'http://example.com',
                            proxy: 'http://proxy.example.com')
# => single request proxied through the proxy
```

This can be used to disable the use of a proxy for a particular request.

```ruby
Contractful.proxy = "http://proxy.example.com/"
Contractful::Request.execute(method: :get, url: 'http://example.com', proxy: nil)
# => single request sent without a proxy
```

## Query parameters

Contractful can render a hash as HTTP query parameters for GET/HEAD/DELETE
requests or as HTTP post data in `x-www-form-urlencoded` format for POST
requests.

Even though there is no standard specifying how this should
work, contractful follows a similar convention to the one used by Rack / Rails
servers for handling arrays, nested hashes, and null values.

The implementation in
[./lib/contractful/utils.rb](Contractful::Utils.encode_query_string)
closely follows
[Rack::Utils.build_nested_query](http://www.rubydoc.info/gems/rack/Rack/Utils#build_nested_query-class_method),
but treats empty arrays and hashes as `nil`. (Rack drops them entirely, which
is confusing behavior.)

If you don't like this behavior and want more control, just serialize params
yourself (e.g. with `URI.encode_www_form`) and add the query string to the URL
directly for GET parameters or pass the payload as a string for POST requests.

Basic GET params:
```ruby
Contractful.get('https://httpbin.org/get', params: {foo: 'bar', baz: 'qux'})
# GET "https://httpbin.org/get?foo=bar&baz=qux"
```

Basic `x-www-form-urlencoded` POST params:
```ruby
>> r = Contractful.post('https://httpbin.org/post', {foo: 'bar', baz: 'qux'})
# POST "https://httpbin.org/post", data: "foo=bar&baz=qux"
=> <Contractful::Response 200 "{\n  \"args\":...">
>> JSON.parse(r.body)
=> {"args"=>{},
    "data"=>"",
    "files"=>{},
    "form"=>{"baz"=>"qux", "foo"=>"bar"},
    "headers"=>
    {"Accept"=>"*/*",
        "Accept-Encoding"=>"gzip, deflate",
        "Content-Length"=>"15",
        "Content-Type"=>"application/x-www-form-urlencoded",
        "Host"=>"httpbin.org"},
    "json"=>nil,
    "url"=>"https://httpbin.org/post"}
```

JSON payload: contractful does not speak JSON natively, so serialize your
payload to a string before passing it to contractful.
```ruby
>> payload = {'name' => 'newrepo', 'description': 'A new repo'}
>> Contractful.post('https://api.github.com/user/repos', payload.to_json, content_type: :json)
=> <Contractful::Response 201 "{\"id\":75149...">
```

Advanced GET params (arrays):
```ruby
>> r = Contractful.get('https://http-params.herokuapp.com/get', params: {foo: [1,2,3]})
# GET "https://http-params.herokuapp.com/get?foo[]=1&foo[]=2&foo[]=3"
=> <Contractful::Response 200 "Method: GET...">
>> puts r.body
query_string: "foo[]=1&foo[]=2&foo[]=3"
decoded:      "foo[]=1&foo[]=2&foo[]=3"

GET:
  {"foo"=>["1", "2", "3"]}
```

Advanced GET params (nested hashes):
```ruby
>> r = Contractful.get('https://http-params.herokuapp.com/get', params: {outer: {foo: 123, bar: 456}})
# GET "https://http-params.herokuapp.com/get?outer[foo]=123&outer[bar]=456"
=> <Contractful::Response 200 "Method: GET...">
>> puts r.body
...
query_string: "outer[foo]=123&outer[bar]=456"
decoded:      "outer[foo]=123&outer[bar]=456"

GET:
  {"outer"=>{"foo"=>"123", "bar"=>"456"}}
```

The `Contractful::ParamsArray` class allows callers to
provide ordering even to structured parameters. This is useful for unusual
cases where the server treats the order of parameters as significant or you
want to pass a particular key multiple times.

Multiple fields with the same name using ParamsArray:
```ruby
>> Contractful.get('https://httpbin.org/get', params:
                  Contractful::ParamsArray.new([[:foo, 1], [:foo, 2]]))
# GET "https://httpbin.org/get?foo=1&foo=2"
```

Nested ParamsArray:
```ruby
>> Contractful.get('https://httpbin.org/get', params:
                  {foo: Contractful::ParamsArray.new([[:a, 1], [:a, 2]])})
# GET "https://httpbin.org/get?foo[a]=1&foo[a]=2"
```

## Headers

Request headers can be set by passing a ruby hash containing keys and values
representing header names and values:

```ruby
# GET request with modified headers
Contractful.get 'http://example.com/resource', {:Authorization => 'Bearer cT0febFoD5lxAlNAXHo6g'}

# POST request with modified headers
Contractful.post 'http://example.com/resource', {:foo => 'bar', :baz => 'qux'}, {:Authorization => 'Bearer cT0febFoD5lxAlNAXHo6g'}

# DELETE request with modified headers
Contractful.delete 'http://example.com/resource', {:Authorization => 'Bearer cT0febFoD5lxAlNAXHo6g'}
```

## Timeouts

By default the timeout for a request is 60 seconds. Timeouts for your request can
be adjusted by setting the `timeout:` to the number of seconds that you would like
the request to wait. Setting `timeout:` will override both `read_timeout:` and `open_timeout:`.

```ruby
Contractful::Request.execute(method: :get, url: 'http://example.com/resource',
                            timeout: 120)
```

Additionally, you can set `read_timeout:`, `write_timeout:` and `open_timeout:`
separately.

```ruby
Contractful::Request.execute(method: :get, url: 'http://example.com/resource',
                            read_timeout: 120, open_timeout: 240)

Contractful::Request.execute(method: :post, url: 'http://example.com/upload',
                            payload: large_body, write_timeout: 30)
```

## Cookies

Request and Response objects know about HTTP cookies, and will automatically
extract and set headers for them as needed:

```ruby
response = Contractful.get 'http://example.com/action_which_sets_session_id'
response.cookies
# => {"_applicatioN_session_id" => "1234"}

response2 = Contractful.post(
  'http://localhost:3000/',
  {:param1 => "foo"},
  {:cookies => {:session_id => "1234"}}
)
# ...response body
```
### Full cookie jar support

The original cookie implementation was very naive and ignored most of the
cookie RFC standards. Response objects carry a `cookie_jar` method that
exposes an HTTP::CookieJar of cookies with full standards-compliant behavior.

## SSL/TLS support

Various options are supported for configuring contractful's TLS settings. By
default, contractful will verify certificates using the system's CA store on
all platforms. (This is intended to be similar to how browsers behave.) You can
specify an :ssl_ca_file, :ssl_ca_path, or :ssl_cert_store to customize the
certificate authorities accepted.

You can also constrain the negotiated TLS protocol versions with
`:ssl_min_version` and `:ssl_max_version`, which map to
`OpenSSL::SSL::SSLContext#min_version=` and `#max_version=`. Version symbols
such as `:TLSv1_2` (or `:TLS1_2`) and integers such as
`OpenSSL::SSL::TLS1_2_VERSION` are accepted:

```ruby
Contractful::Request.execute(method: :get, url: 'https://example.com/resource',
                            ssl_min_version: :TLSv1_2)
```

### SSL Client Certificates

```ruby
Contractful::Resource.new(
  'https://example.com',
  :ssl_client_cert  =>  OpenSSL::X509::Certificate.new(File.read("cert.pem")),
  :ssl_client_key   =>  OpenSSL::PKey::RSA.new(File.read("key.pem"), "passphrase, if any"),
  :ssl_ca_file      =>  "ca_certificate.pem",
  :verify_ssl       =>  OpenSSL::SSL::VERIFY_PEER
).get
```
Self-signed certificates can be generated with the openssl command-line tool.

## More

Need caching, more advanced logging or any ability provided by Rack middleware?

The historical rest-client-components project (Rack-middleware-style
request processing for the upstream gem) lives at
http://github.com/crohr/rest-client-components — it predates contractful
and is not tested against it.

## Credits
| | |
|-------------------------|---------------------------------------------------------|
| **REST Client Team**    | Andy Brody                                              |
| **Creator**             | Adam Wiggins                                            |
| **Maintainers Emeriti** | Lawrence Leonard Gilbert, Matthew Manning, Julien Kirch |
| **Major contributions** | Blake Mizerany, Julien Kirch                            |

A great many generous folks have contributed features and patches.
See AUTHORS for the full list.

## Legal

Released under the MIT License: https://opensource.org/licenses/MIT

Photo of the International Space Station was produced by NASA and is in the
public domain.

Code for reading Windows root certificate store derived from work by Puppet;
used under terms of the Apache License, Version 2.0.
