# API — public surface reference

This document is the normative list of contractful's public API. Names
documented here are covered by semantic versioning: removing or changing one
requires a major release. Anything not listed here (underscore-prefixed
machinery like `__own_contract_config`, private helpers) is internal and may
change in any release. The contract-first layer is part of the public surface
and follows the same rules. Version markers in parentheses refer to the
upstream rest-client release line in which a feature first appeared;
contractful 0.1.0 ships all of them.

## Module-level entry points

```ruby
Contractful.get(url, headers = {})
Contractful.post(url, payload, headers = {})
Contractful.put(url, payload, headers = {})
Contractful.patch(url, payload, headers = {})
Contractful.delete(url, headers = {})
Contractful.head(url, headers = {})
Contractful.options(url, headers = {})
Contractful::Request.execute(options)   # full option surface, returns Response
```

Non-2xx responses raise the mapped exception unless a block is given (block
form returns the response and lets the caller decide — see README "Result
handling").

## Request options

All accepted by `Request.execute` (and the corresponding per-call contract
meta options):

| Option | Meaning |
| --- | --- |
| `:method`, `:url` | Verb symbol and target URL (required) |
| `:payload` | Hash/ParamsArray (form or JSON), String, IO/stream, or multipart file parts |
| `:headers` | Header hash |
| `:user`, `:password` | Basic-auth credentials |
| `:timeout`, `:open_timeout`, `:read_timeout`, `:write_timeout` | Total and phase timeouts (seconds) |
| `:max_redirects` | Redirect cap (default 10) |
| `:ssl_ca_file`, `:ssl_client_cert`, `:ssl_client_key` | TLS trust and client identity |
| `:ssl_min_version`, `:ssl_max_version` | Protocol floor/ceiling; normalized via `normalize_ssl_version` (accepts `:TLSv1_2`-style symbols, `:TLS1_2`-style symbols and OpenSSL constants) |
| `:verify_ca` / `:verify_callback` | Certificate verification control |
| `:cookies` | Cookie hash or jar |
| `:persistent` | Use the keep-alive connection pool (2.3+) |
| `:max_retries`, `:retry_interval` | Automatic retry count and base delay (exponential backoff) (2.3+) |
| `:retry_after`, `:max_retry_after` | Honor server `Retry-After` and cap its value (2.5+) |
| `:log` | Per-request logger override |
| `:block_response` | Raw response handler |

## Resource

```ruby
site = Contractful::Resource.new('https://api.example.com', user:, password:, headers:)
site['orders'].get                      # nested path resources
site['orders'].post(payload_hash)       # same option surface as Request
```

## Response

`Contractful::Response` is a String-like object (`#body`, `#to_s`) plus:

| Method | Meaning |
| --- | --- |
| `#code` / `#to_i` | HTTP status |
| `#headers` | Downcased header hash |
| `#raw_headers` | Original header block |
| `#history` | Redirect chain responses |
| `#cookies`, `#cookie_jar` | Set cookies as hash / jar |
| `#json(**opts)` | JSON.parse of the body (2.3+) |
| `#rate_limit` | Parsed `RateLimit` or `nil` when absent (2.5+) |
| `#rate_limited?` | Strict boolean: 429 or exhausted quota (2.5+) |

## Exceptions

```text
Contractful::Exception < RuntimeError          # .response .http_code .http_body .http_headers .retryable?
├── ExceptionWithResponse                      # retryable? = status in RETRIABLE_STATUSES
│   ├── RequestFailed                          # unmapped failure statuses
│   │   └── one class per HTTP status: NotFound, Unauthorized, Conflict,
│   │       TooManyRequests, InternalServerError, ... (+ legacy aliases)
│   └── Exceptions::Timeout < RequestTimeout
│       ├── OpenTimeout  ├── ReadTimeout  └── WriteTimeout (2.3+)
├── ServerBrokeConnection
└── SSLCertificateNotVerified
```

Classification: `Contractful::Exceptions::RETRIABLE_STATUSES` is
`[408, 425, 429, 500, 502, 503, 504]`; `Exceptions.retryable?(status_or_exception)`
also classifies network errors (`SocketError`, `Errno::*`, `Net::*Timeout`,
`::Timeout::Error`). All other statuses are terminal — retrying will not fix
a bad token or a bad payload.

## Contract DSL (`Contractful::Contract`)

Class-level macros (on the client class):

| Macro | Meaning |
| --- | --- |
| `base(url)` | Absolute http(s) base URL; trailing slashes stripped |
| `default_headers(hash)` | Merged down the ancestor chain (reader form with no args) |
| `strict_params(flag)` | Strict unknown-param rejection (default on) |
| `payload_style(:json \| :form)` | Class default payload routing |
| `auth bearer: / api_key: / basic:` | Scheme declaration; values may be callables, invoked per request; `api_key:` accepts an array for dual-header schemes and `in: :query` |
| `idempotency_header(name)`, `idempotency_generator(callable)` | Key header customization |
| `before_request { \|ctx\| }` | Mutable context: `definition:, method:, url:, headers:, payload:, query:` |
| `after_response { \|resp\| }` | Observe validated responses |
| `resource :posts, path:, only:, except:, update_with:, singular:` | Generates the five CRUD contracts (non-strict) |
| `contract :name, 'VERB /path' do ... end` | Declare one operation |

Inside a contract block:

| Declaration | Meaning |
| --- | --- |
| `param :name, Type, required:, default:, inclusion:, min:, max:, length:, pattern:, coerce:, description:` | Closed-schema param (String, Integer, Float, `:boolean`, Array, Hash, any class, any Proc) |
| `responds 200, (200..299), type: Array/:hash/:json/...` | Expected statuses + body shape; declaring 4xx/5xx converts them to returned values and judges everything by the contract |
| `response_field :name, type, required:, strict:` | Open-schema response binding: required+type bind; undeclared fields are data |
| `verify_response { \|resp, parsed\| }` | Custom assertion; falsey raises `UnexpectedResponse` |
| `paginated style: :cursor, cursor_param:, next_cursor_path:, items_path:` / `style: :offset, offset_param:, limit_param:, has_more_path:` | Pagination strategy |
| `idempotent true` | Inject a stable idempotency key header |
| `auth false` | Opt out of class auth |
| `payload_style`, `strict_params` | Per-contract overrides |

Per-call meta options: `_headers`, `_timeout`, `_open_timeout`,
`_read_timeout`, `_write_timeout`, `_persistent`, `_max_retries`,
`_retry_interval`, `_idempotency_key`, `_max_pages`.

Generated per contract `:name`: `name(**params)`, `name_url(**params)`, and
for paginated contracts `name_pages(**params)` (lazy Enumerator of validated
pages) and `all_name(**params)` (flat collector). Reflection:
`contracts`, `contract_names`, `contract?`, `contract_for`,
`Definition#describe`; dynamic dispatch conveniences `call_*`, `*_contract`,
`has_*?` with `respond_to_missing?` support. Instance-level overrides:
`Client.new(base:, headers:)`.

Contract errors, all rooted at `Contractful::Contract::Error`:
`InvalidDefinition` (declaration time), `MissingBaseUrl`, `MissingParam`,
`UnknownParam`, `InvalidParam` (pre-flight), `UnexpectedResponse`
(`#response` attached; response-contract violations), `PaginationError`
(missing stop condition / `_max_pages` exceeded).
