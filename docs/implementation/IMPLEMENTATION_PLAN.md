# IMPLEMENTATION PLAN

Where the project is, what comes next, and in what order. Each workstream
decomposes into one-commit tasks — the established cadence of this
repository is: implement, green the suite, commit and push, one feature at
a time. Requirements referenced here are defined in
[docs/requirements/REQUIREMENTS.md](../requirements/REQUIREMENTS.md).

## Current baseline (v2.5.0, branch `feature/contract-first`, PR #2 open)

Shipped across 2.2 → 2.5: full Ruby 3.0–4.0 modernization with CI matrix;
automatic retries with exponential backoff and `Retry-After`; persistent
connections via a thread-safe pool; `Response#json`; and the complete
contract-first layer — typed closed-schema params, open-schema response
fields, contract auth, idempotency keys, cursor/offset pagination with
metaprogrammed enumerators, rate-limit parsing, callbacks, CRUD macro,
reflection and dynamic dispatch. Unit + integration suites green; contract
specs now included in `rake spec:unit` (fixed during the documentation
workstream).

## Workstreams

### W1 — Documentation suite (this workstream, status: in progress)

Deliver the full project documentation system: AGENTS.md, CONTRIBUTING.md,
PRD/DESIGN/ARCHITECTURE/API/DATABASE at the root; requirements, ADRs,
implementation, engineering, security, operations and agent guides under
`docs/`. Done when every document exists with real content, README links
the map, and CI is green. Also carries the opportunistic fix that included
`spec/unit/contract/` in the CI unit task.

### W2 — Merge PR #2 and tag (status: pending, operator action)

PR #2 carries 2.4.0 + 2.5.0. After merge: tag `v2.4.0` and `v2.5.0` on
master (tagging requires operator approval per AGENT_TOOL_POLICY.md),
verify matrix on master, then the release cadence in DELIVERY.md. Note:
`gem push` remains blocked on RubyGems credentials.

### W3 — OpenAPI import helper (REQ-N01, status: shipped, 2.6.0)

A separate, opt-in reader that converts an OpenAPI 3.x document into
`contract` declarations (source-to-source, run at development time, not a
runtime dependency). Shipped as `require 'contractful/contract/openapi_import'`:
`.import` builds Definitions (typed params with closed-schema constraints,
payload styles, statuses incl. `2XX` wildcards, open-schema response
fields), `.to_ruby` renders a client class from those same definitions and
the output round-trips through `Definition#describe`; every lossy mapping
decision is reported on `Import#notes`. Verified by
`spec/unit/contract/openapi_import_spec.rb`.

### W4 — Recorded-sequence test helper (REQ-N02, status: shipped, 2.6.0)

Contracts deliberately do not express ordering, timing or cross-call state
machines. Shipped as `require 'contractful/contract/sequence'`: a sequence
fixture (YAML/JSON under the consumer's control) drives the contract
client through N recorded interactions with WebMock, failing on the first
contract violation with the step number attached. `expect_request`
assertions pin outgoing path/query/header/payload subsets; `before_step` /
`after_step` hooks carry the stateful rules (token refresh, rate-limit
windows). Verified by `spec/unit/contract/sequence_spec.rb`.

### W5 — Downstream client enablement (status: opportunity)

The motivating downstream consumer is a DhanHQ trading client. Investigation
(concluded 2026-10): **DhanHQ publishes no machine-readable API spec** —
documentation is prose, the dhan-oss org hosts client libraries in other
languages, and community Postman collections are not authoritative.
Therefore the contract must be **authored from the docs** using this DSL:
dual-header auth via `api_key:` array (`access-token` + `client-id`),
prose-documented rate limits yielding `nil` until headers appear, error-code
classification from the vendor annexure mapped to retryable/terminal. This
validates W3/W4 from the consumer side; it lives in its own repository.

### W6 — Release engineering (ongoing)

Keep `history.md` current, tag releases post-merge (W2), and maintain the
release checklist in DELIVERY.md. Gem publication to RubyGems is
maintainer-only; when credentials exist, `rake all:release` covers both
platforms.

## Sequencing and dependencies

```text
W1 (docs) ──► W2 (merge+tag) ──► W6 (release cadence)
                   │
                   ├──► W3 (OpenAPI import)
                   ├──► W4 (sequence testing)
                   └──► W5 (downstream client, separate repo)
```

W3 and W4 are independent of each other; both benefit from W2 landing the
contract layer on master first. W5 can start any time in its own repo but
informs W3/W4 priorities.

## Definition of done (per workstream)

Requirements rows moved to `implemented` with verifying specs green on the
full matrix; README/history updated; both gemspecs build; one commit per
task with conventional messages; PR (if any) updated.
