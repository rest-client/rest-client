# ADR 0002 — Contract-first architecture for API client development

- **Status:** Accepted (2026-10, shipped as 2.4.0/2.5.0 via PR #2)
- **Context:** SDK authors hand-write client code that drifts from the APIs
  it wraps

## Context

Hand-written API clients are code-first: the implementation exists first and
the interface description, at best, is retro-fitted documentation. That
order produces predictable failures — client methods accept parameters the
API rejects, misparse responses because a vendor added a field, silently
misinterpret order states, and cannot tell a transient failure from a
terminal one. The alternative is contract-first: a machine-checkable
interface declaration is written (and reviewed, and versioned) *before* the
implementation, and the SDK's types, validation, mocks and tests derive from
that declaration.

Two design principles anchor the decision:

- **Request schemas are closed.** We control what we send, so bad input is
  rejected *before* any network call: unknown parameters, wrong types,
  out-of-range values and malformed enum members raise immediately.
- **Response schemas are open.** Required fields and their types bind, but
  new fields and new enum values are additive — unknown values are data,
  not errors. Raising on an unknown response field would break every client
  the day the vendor ships a harmless addition.

A contract must also be able to carry the semantics that make retries and
production behavior safe: authentication schemes, an error model that
classifies retryable vs terminal failures, idempotency keys for POSTs,
pagination strategies, and rate-limit header awareness. What a per-call
contract deliberately does **not** express is ordering, timing and
cross-call state machines (rate-limit windows, order lifecycles); those are
tested separately against recorded call sequences rather than encoded in
declarations.

## Decision

Build `Contractful::Contract` on top of the existing request pipeline:

1. Contracts are Ruby DSL declarations (`contract :name, 'VERB /path' do
   ... end`) evaluated at class load time into `Definition` objects. The
   declaration **is** the implementation — there is no imperative request
   code to drift.
2. Typed params enforce closed schemas: `required`, types with coercion,
   `inclusion:` enums, and `min/max/length/pattern` constraints, all checked
   pre-flight, raising `MissingParam` / `UnknownParam` / `InvalidParam`.
3. Response declarations enforce open schemas: `responds` for statuses and
   body shape, `response_field` for required fields and types only.
   Declared error statuses return as values instead of raising.
4. The contract carries auth (`bearer:`/`api_key:`/`basic:`, callable
   credentials), idempotency keys (stable across retries), pagination
   (cursor/offset styles with metaprogrammed page enumerators), and
   rate-limit parsing on every response.
5. Errors are exceptions, rooted at `Contractful::Contract::Error`. Throwing
   is the correct default on order-critical paths: a silently misparsed
   order status is worse than an exception.
6. **Zero new runtime dependencies.** The contract layer is pure Ruby
   metaprogramming over the existing pipeline; no JSON-Schema engine, no
   OpenAPI parser ships in the gem.

## Alternatives considered

- **openapi-generator with the Ruby target:** rejected as the primary path —
  its output is rarely idiomatic Ruby, adds a build step, and still leaves
  the generated code drifting from hand-written glue. A *read-only* OpenAPI
  import helper that emits contract declarations remains a planned
  convenience (REQ-N01), keeping the DSL as the single runtime truth.
- **JSON-Schema / dry-schema validation engine:** rejected as a runtime
  dependency — the DSL expresses the closed/open semantics directly with no
  dependency cost. Adapters can come later as opt-ins.
- **Pact-style consumer contracts:** a different tool for a different
  problem — Pact records consumer expectations for provider verification; it
  is not an API specification and does not replace one.
- **Server-side enforcement of the same document:** valuable for teams that
  own both ends (Rails `openapi_first` / `committee` enforce a shared spec
  at the server boundary); out of scope for this gem, but the
  closed-request/open-response rules here mirror that split so one mental
  model covers both.

## Consequences

- Positive: client methods, URL builders, validation, pagination and
  introspection are generated from one reviewed declaration; bad input dies
  pre-network; vendor additions do not break clients; downstream consumers
  (a DhanHQ trading client, for example) get a clean authoring path even
  when the vendor publishes no machine-readable spec — DhanHQ's docs are
  prose only, so its contract must be authored from documentation, which is
  exactly what the DSL is for.
- Costs: metaprogramming complexity (bounded by ADR 0003); contracts cannot
  express ordering/timing — mitigated by planned recorded-sequence test
  helpers (REQ-N02); a DSL must be learned (mitigated by README examples
  and `Definition#describe` introspection).
