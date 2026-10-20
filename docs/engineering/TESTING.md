# TESTING — strategy, organization and commands

contractful's correctness story is its test suite: a fast offline unit
suite covering every module (including the full contract DSL), an
integration suite with WebMock-stubbed HTTP behavior plus a small
deliberate live component, and packaging verification via gem builds. If a
behavior is not covered by a spec, its correctness is an opinion.

## Stack

- **RSpec** ~> 3.13 — all specs
- **WebMock** >= 3.19, < 5 — HTTP stubbing for offline specs
- **mise + Ruby 4.0.7** — reference runtime (see
  [SETUP.md](../implementation/SETUP.md)); CI additionally verifies the
  3.0–4.0 matrix

## Organization

```text
spec/
├── unit/                  # fast, offline, one file per lib module
│   ├── request_spec.rb    # pipeline: options, redirects, retries, SSL
│   ├── contract/          # the DSL surface, one file per concept
│   │   ├── param_spec.rb               # typing + closed-schema constraints
│   │   ├── response_validation_spec.rb # responds semantics
│   │   ├── response_fields_spec.rb     # open-schema bindings
│   │   ├── auth_spec.rb, idempotency_spec.rb, pagination_spec.rb
│   │   ├── callbacks_spec.rb, resource_spec.rb, introspection_spec.rb
│   │   └── executor_spec.rb, definition_spec.rb
│   ├── connection_pool_spec.rb, rate_limit_spec.rb, ...
│   └── ...
├── integration/           # HTTP behavior through the real Request path
│   ├── integration_spec.rb, request_spec.rb   # WebMock-stubbed
│   └── httpbin_spec.rb    # LIVE network (WebMock disabled) — see below
└── helpers.rb, spec_helper.rb
```

Rules of placement: unit specs never touch real sockets (they exercise
`Request` with WebMock or stubbed transports); integration specs drive the
full request path; only `httpbin_spec.rb` and the contract live specs touch
the network, because TLS, real headers and redirect chains deserve at least
one truthful end-to-end verification.

## Commands

```sh
bundle exec rake spec:unit         # spec/unit/** — includes contract/ (fixed to do so)
bundle exec rake spec:integration  # spec/integration/* — includes the live httpbin specs
bundle exec rake spec              # everything (default task)
bundle exec rake doc               # specdoc dry-run
```

CI (`.github/workflows/ci.yml`) runs `spec:unit` and `spec:integration` on
Ruby 3.0–4.0, plus an experimental non-blocking `ruby-head` job. A red
matrix blocks merge; a red `ruby-head` is a warning about tomorrow.

## Conventions and known traps

Conventions first: spec files mirror `lib/` paths; contract specs document
the DSL semantics and are the best reading material before changing
contract behavior; every bug fix lands with a spec that fails without the
fix; the suite runs with randomized ordering, so no spec may depend on
another's state.

Traps that have actually bitten this codebase — codify, don't rediscover:

1. **rspec-mocks kwargs ambiguity.** A bare `.with(hash)` can be interpreted
   as keyword arguments on modern Ruby. Wrap expected hashes in explicit
   braces: `.with({ headers: { 'Accept' => 'json' } })`.
2. **WebMock query matching.** A stub registered with a bare URL matches
   only query-less requests. Contracts with default params produce query
   strings — stub with `hash_including` or a full URL-with-query.
3. **`base64` is gone** on Ruby 4.0: never `require 'base64'` in specs;
   use `String#unpack1('m')` for basic-auth-style decoding.
4. **`URI.parse('http:///').hostname`** is `''` on Ruby 3.4+, `nil` before —
   version-agnostic specs assert `hostname.to_s.empty?`.
5. **Constant shadowing inside `Contractful::Request`:** `Exception` and
   `Timeout` resolve to the gem's own constants; specs that stub top-level
   network errors must reference `::Timeout::Error` and friends explicitly.
6. **Redirect-following in the suppression path:** when a contract declares
   error statuses, execution returns responses instead of raising, but
   redirects must still be followed manually there — specs for new
   response-validation features must cover the redirect-in-suppression
   case.

## Coverage expectations

The project does not chase a coverage percentage; it enforces coverage by
requirement. Every row in
[REQUIREMENTS.md](../requirements/REQUIREMENTS.md) names its verifying
specs, and new `lib/` code without a verifying spec is an incomplete
change. Critical paths — SSL normalization, timeout plumbing, retry
classification, connection-pool keying, contract validation ordering —
must have negative cases (the violation, not just the success).

## Contract-layer testing philosophy

Request-side validation is tested as a **closed schema**: for each param
family, specs assert rejection (the precise error class, raised before any
HTTP interaction) of missing, unknown, wrongly-typed and out-of-constraint
values. Response-side validation is tested as an **open schema**: required
fields and types bind, unknown fields pass through untouched, new enum
members are data, and values are never coerced. What the specs deliberately
do *not* cover is ordering/timing across calls — that is the recorded-
sequence helper's job (REQ-N02,
`require 'contractful/contract/sequence'`): sequence fixtures replay
recorded vendor responses through a contract client, fail on the first
violation with the step number attached, and carry stateful rules in
`before_step`/`after_step` hooks. If you are adding semantics that span
calls (like pagination already does), say so explicitly in the feature
spec and test the sequence with WebMock-orchestrated pages.

## Release QA checklist

Before tagging a release, maintainers run the full `rake spec` on the
reference Ruby, spot-check the live httpbin specs, build both gemspecs,
install the built Ruby-platform gem into a scratch gemset and run the
README smoke snippets. The suite being green is necessary, not sufficient —
packaging and docs are part of quality.
