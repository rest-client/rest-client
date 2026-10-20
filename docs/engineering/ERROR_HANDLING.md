# ERROR HANDLING — exception model and design rules

contractful's error philosophy is stated in [DESIGN.md](../../DESIGN.md)
and enforced here: **exceptions are the default**, every raise is a precise
class, response-bearing errors carry the full response, and nothing in the
library swallows an error or converts an unexpected result into `nil`. This
document is the reference for what raises, when, and what it carries.

## The transport error tree

```text
Contractful::Exception < RuntimeError
  attributes: .response  .original_exception
              .http_code .http_headers .http_body
              .retryable?
│
├── ExceptionWithResponse
│   ├── RequestFailed                       # unmapped failure status
│   │   └── one class per status (NotFound, Unauthorized, Forbidden,
│   │       Conflict, TooManyRequests, InternalServerError, ...)
│   │       + legacy aliases (ResourceNotFound, RequestEntityTooLarge, ...)
│   └── Exceptions::Timeout < RequestTimeout
│       ├── OpenTimeout     # connection establishment
│       ├── ReadTimeout     # response stalled
│       └── WriteTimeout    # request upload stalled (2.3+)
│
├── ServerBrokeConnection     # connection died mid-exchange
└── SSLCertificateNotVerified
```

Every `ExceptionWithResponse` gives you the evidence: `e.response.body`,
`e.http_code`, `e.http_headers`. Timeout exceptions carry the wrapped
`Net::*Timeout` in `.original_exception`.

## Retryable vs terminal classification

Part of the error model itself, not caller folklore:

| Classification | Members | Rationale |
| --- | --- | --- |
| Retryable statuses | 408, 425, 429, 500, 502, 503, 504 (`Exceptions::RETRIABLE_STATUSES`) | Transient by nature or gateway-scoped |
| Retryable network failures | `::Timeout::Error`, `Net::OpenTimeout/ReadTimeout/WriteTimeout`, `SocketError`, `EOFError`, `Errno::ECONNRESET/ECONNABORTED/EPIPE/ECONNREFUSED/EHOSTUNREACH/ENETUNREACH` (`Exceptions.network_errors`) | The wire failed before an answer existed |
| Terminal | everything else — 401, 403, 404, 409, 422, 501, ... | Retrying cannot fix a bad credential, missing resource or bad payload |

APIs: `exception.retryable?` on instances, and
`Contractful::Exceptions.retryable?(status_or_exception)` for integers and
foreign network errors. The automatic retry machinery (2.3+) uses exactly
this classification, honors server `Retry-After` (delta-seconds or
HTTP-date, capped by `:max_retry_after`), and falls back to
`RateLimit-Reset` on a 429 that lacks `Retry-After`.

## The contract error tree

Rooted separately at `Contractful::Contract::Error` because contract
violations are semantic, not transport:

```text
Contractful::Contract::Error < StandardError
├── InvalidDefinition        # declaration-time: bad request line, verb,
│                            #   name, param options, response types
├── MissingBaseUrl           # execution-time: no base configured
├── ParamError
│   ├── MissingParam         # required param absent (incl. path params)
│   ├── UnknownParam         # undeclared param in strict mode
│   └── InvalidParam         # coercion/constraint failure
├── UnexpectedResponse       # .response attached: undeclared status,
│                            #   body type/shape mismatch, failed
│                            #   verify_response, broken response_field
└── PaginationError          # no stop condition / _max_pages exceeded
```

Timing rules — the part that makes the contract layer trustworthy:

- **Definition errors raise when the class loads** (`InvalidDefinition`).
  A client that cannot be trusted statically never reaches a request.
- **Param errors raise before the transport is touched.** `InvalidParam`
  for a `min: 1` integer fires pre-network, identical for `0` and `"0"`.
- **Response errors raise on return.** An `orderId` that arrives as an
  integer when the contract declares `:string` raises
  `UnexpectedResponse` with the response attached — the caller decides
  what to do, the library refuses to guess.
- **Contract errors are never retried as transport errors.** A contract
  violation is deterministic; retrying it reproduces it.

## Message contract

Every exception message must let a user act without a debugger:

- Param errors name the param, the contract, the expectation and the
  received value (`quantity must be >= 1 for :create_order, got 0`).
- Response errors name the expectation and the reality (status, expected
  vs actual type, missing required field).
- Transport errors state the phase (open/read/write) and carry the
  response when one exists.

Do not log-and-reraise inside the library; the caller owns logging
(see [OBSERVABILITY.md](../operations/OBSERVABILITY.md)).

## Rules for library code

1. Raise subclasses from the two documented roots — never bare
   `RuntimeError`/`StandardError`, never `raise "string"`.
2. Never rescue an error to return a default; if a fallback is genuinely
   the feature, the API makes it explicit (block-style suppression,
   `responds 404`).
3. Attach evidence: response objects on response-bearing errors,
   `original_exception` for wrapped network errors.
4. Preserve the thread of causality when wrapping (`original_exception`),
   as the timeout classes do for `Net::*Timeout`.
5. Beware lexical shadowing inside `Request`: `Exception` there is
   `Contractful::Exception`, not `::Exception` — the retry loop must (and
   does) scope top-level constants explicitly.

## Guidance for library users

- Rescue `Contractful::Exception` for transport-shaped failures, specific
  status classes (`Contractful::NotFound`) for specific handling, and
  `Contractful::Contract::Error` around contract clients; narrow down as
  needed. Use `retryable?` for policy, not message matching.
- Prefer declaring expected failure statuses in contracts (`responds 200,
  404`) over rescuing `ResourceNotFound` — the contract makes the
  expectation visible and returns the error response as data.
- Never rescue `Exception` broadly in application code around HTTP calls;
  rescue the documented roots so programming errors still crash loudly.
