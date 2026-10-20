# DESIGN — Developer-experience and interface design

contractful has no graphical UI; its "design" surface is the experience of a
Ruby developer reading, writing and debugging code against the gem. This
document records the design principles behind that experience and the rules
new features must follow, so the gem keeps one coherent voice instead of
accumulating whatever interface each contributor was used to elsewhere.

## Design principles

1. **Simple things simple, hard things possible.** `Contractful.get(url)` is
   one line with zero configuration; SSL client certificates, proxy
   settings and per-request timeouts are all reachable without abandoning
   the same API.
2. **Exceptions over silent failure.** A wrong status raises a specific
   exception carrying the response; a contract violation raises before any
   network traffic. The library never converts an unexpected result into
   `nil`, an empty hash, or a log line. The worst debugging session is the
   one where a misparsed value propagates silently.
3. **Closed requests, open responses.** We control what we send, so request
   validation is strict and eager (unknown params, wrong types, out-of-range
   values all raise pre-flight). Servers evolve independently of us, so
   response validation binds only declared required fields and types —
   unknown fields and new enum members are data, not errors.
4. **Declarations over imperative code.** Where a behavior can be expressed
   as a declaration (a param type, a pagination style, an auth scheme), the
   DSL takes the declaration and metaprogramming does the rest. Imperative
   escape hatches (`verify_response` blocks, `before_request` callbacks)
   exist for what declarations cannot express.
5. **Progressive disclosure.** Three tiers with a smooth gradient:
   one-liner module methods → `Resource` for URL-structured APIs →
   `Contractful::Contract` for full contract-first clients. Each tier builds
   on the same `Request`/`Response` core, so nothing learned is wasted.

## Interface ergonomics

- Keyword arguments for options; positional arguments only for the primary
  nouns (`url`, `payload`). Options hashes from the 1.x era remain accepted
  for compatibility but are not the pattern for new features.
- **Underscore-prefixed per-call meta options** (`_headers`, `_timeout`,
  `_persistent`, `_max_retries`, ...) configure the transport on contract
  calls without polluting the user's param namespace. New cross-cutting
  request options must follow this convention rather than inventing new
  top-level names.
- Generated names follow fixed suffix grammar so users can predict them:
  `#{name}` executes a contract, `#{name}_url` builds the URL,
  `#{name}_pages` enumerates validated pages, `all_#{name}` collects every
  item across pages, `#{name}_contract` returns the definition,
  `has_#{name}?` tests existence. Any new metaprogrammed family must join
  this grammar instead of improvising.
- Params mirror the API being wrapped: if the vendor documents
  `pageToken`, the param is `pageToken`. The contract layer is a typed
  boundary, not a renaming layer.

## Error design

- Every error a user can hit is a class they can rescue specifically, and
  every class name states the problem (`Contractful::NotFound`,
  `Contract::UnknownParam`, `Contract::PaginationError`).
- Response-bearing exceptions attach the full `response` object
  (`.response`, `.http_code`, `.http_headers`, `.http_body`); contract
  violations attach what failed and why in the message. A user must never
  need a debugger to learn what went wrong.
- Classification is part of the model: `Exception#retryable?` and
  `Exceptions.retryable?` distinguish transient (timeouts, 408/425/429/5xx)
  from terminal (bad credentials, missing resources) so callers can make
  policy decisions without string-matching messages.
- New error classes nest under the right root: transport failures under
  `Contractful::Exception`, contract semantics under
  `Contractful::Contract::Error`. Never raise bare `RuntimeError` or
  `StandardError` from library code.

## Configuration design

- Defaults are safe and boring: TLS verification on, redirects followed for
  idempotent verbs, retries off until asked for. Opt-in for anything with
  side effects.
- Validation happens at declaration time wherever possible — a bad
  `payload_style`, an invalid request line or a nonsense `inclusion:` range
  raises `InvalidDefinition` when the class loads, not when a request fires
  at 3 a.m.
- Inheritance semantics for client class hierarchies are fixed and
  documented: config and callbacks accumulate root-most-first, nearest
  definition wins for contracts and scalars. New settings must specify
  their inheritance behavior explicitly.

## Documentation design

- README examples are runnable and truthful — they are copied into specs
  and smoke-tested against httpbin.org before releases.
- Every public method name in `lib/` carries YARD documentation; the
  generated method families document their generation source.
- `history.md` is the changelog of record: one section per release, every
  user-facing change listed with its behavior, not its diffstat.
- Deprecations get one minor version of warnings before removal, and the
  removal is called out in `history.md` as a breaking change at the next
  major.
