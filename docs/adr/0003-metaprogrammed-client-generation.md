# ADR 0003 — Heavy metaprogramming for client generation

- **Status:** Accepted (2026-10, shipped as 2.4.0 via PR #2)
- **Context:** the contract layer must generate client methods, URL
  builders, page enumerators and introspection from declarations without a
  code-generation build step

## Context

ADR 0002 decided that contracts are declarations compiled into behavior.
Three implementation strategies were possible:

1. **Code generation to files** (openapi-generator style): a build step
   writes Ruby source files that are committed or shipped.
2. **Pure `method_missing` dispatch:** no generated methods at all; every
   `client.list_orders` call falls through to `method_missing`, which looks
   up the contract at call time.
3. **`define_method` compilation at declaration time:** including the DSL
   module immediately creates real instance methods (plus `_url` builders
   and, for paginated contracts, `_pages` / `all_` collectors) from each
   `Definition`.

## Decision

Strategy 3, with `method_missing` reserved for conveniences only:

- `Contract::ClassMethods#__define_contract_methods` uses `define_method`
  exactly once per contract per family (`name`, `name_url`, `name_pages`,
  `all_name`) at `contract`/`resource` declaration time. Generated methods
  are real methods: they appear in `#methods`, respond to `respond_to?`,
  run at full speed, and are visible to editors and tooling.
- `Contract::InstanceMethods#method_missing` handles only the three
  convenience families — `call_*` (execute by name), `*_contract` (fetch
  the Definition), `has_*?` (existence predicate) — always guarded by a
  contract lookup, always paired with `respond_to_missing?`, and always
  deferring to real methods first (a contract literally named `call_ping`
  is unaffected by the `call_*` pattern).
- DSL blocks are `instance_eval`'d against the `Definition`, so a contract
  body reads as a plain sequence of declarations; the macro machinery
  passes blocks through `Definition.new` in one place.
- Class configuration (base URL, headers, auth, strictness, callbacks)
  lives in per-class `Config` objects merged down the ancestor chain
  (root-most first; nearest definition wins for contracts). No global
  registry, no shared mutable state.
- A `RESERVED_NAMES` list prevents contracts from shadowing object identity
  and sending primitives (`initialize`, `inspect`, `send`, ...).

## Alternatives considered

- **Code generation to files:** rejected — a build step, committed artifacts
  that drift from their contract source, and diffs that mix generated and
  reviewed code. The Ruby-idiomatic cost of `define_method` is lower and
  entirely at load time.
- **Pure `method_missing`:** rejected — slower hot paths, invisible to
  `respond_to?` without careful auditing, opaque stack traces, and tooling
  blind spots. It remains only for the convenience families where dynamic
  behavior is the feature.

## Consequences

- Positive: declaration-time validation (`InvalidDefinition` raised when
  the class loads, not when a request fires); predictable name grammar;
  introspection (`contracts`, `contract_for`, `Definition#describe`) that
  stays truthful because it reads the same definitions that generated the
  methods; no generated code in the diff.
- Costs and mitigations: stack traces pass through generated methods —
  mitigated by the single generation site and descriptive `Definition#inspect`;
  metaprogramming demands discipline — mitigated by confining `eval`-class
  behavior to `instance_eval` of user-supplied blocks and forbidding ad-hoc
  `eval`; name collisions with Ruby core methods — mitigated by
  `RESERVED_NAMES` and real-method precedence over `method_missing`.
