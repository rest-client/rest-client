# Agent workflows — how agents execute work in this repository

This document defines the phase-by-phase workflow AI agents follow for
non-trivial tasks in contractful. The stable rules live in
[AGENTS.md](../../AGENTS.md) at the repository root; this file is the
operational playbook. The phases are sequential, but small fixes may collapse
them — what may never collapse is the verification and review phase.

## Phase 0 — Session bootstrap

Before any work: check out the intended branch, confirm the environment and
establish a green baseline. In the reference environment Ruby comes from mise
and there is no system Ruby:

```sh
export PATH="$HOME/.local/bin:$PATH"
mise exec -- ruby -v          # expect 4.0.x
mise exec -- bundle install   # first run of a fresh checkout
mise exec -- bundle exec rake spec:unit
mise exec -- bundle exec rake spec:integration
```

Record the baseline example/failure counts. If the baseline is red, stop and
diagnose before starting anything new — never build on a red suite. Read the
git log of the target branch to understand where the previous session left
off.

## Phase 1 — Discover

Inspect the repository before proposing changes: the relevant `lib/` and
`spec/` files, [API.md](../engineering/API.md) for the public surface,
[ARCHITECTURE.md](../engineering/ARCHITECTURE.md) for where the change
belongs, and recent `history.md` entries for context on how similar features
were introduced. For contract-layer work, read the existing specs under
`spec/unit/contract/` — they document the intended semantics better than any
prose.

## Phase 2 — Resolve

Identify ambiguities: conflicting requirements, missing acceptance criteria,
undefined behavior at boundaries. For each one, either pick the conservative
interpretation or stop and ask the operator. Record every assumption in the
commit message or PR body so a reviewer can challenge it later. An agent must
never resolve a product-level ambiguity silently — guess conservatively and
surface it, or escalate.

## Phase 3 — Specify

For a feature: add or update its row in
[docs/requirements/REQUIREMENTS.md](../requirements/REQUIREMENTS.md) with an
ID, acceptance criteria and status `in-progress`, and write the public API
sketch first (contract declaration, method names, error behavior). For
contract-layer features, the declaration *is* the spec — design what users
will write before implementing how it executes. For fixes: identify the spec
that should have caught the bug.

## Phase 4 — Plan

Break the work into ordered tasks that each fit in one commit: one concern,
one commit, green suite between commits. Define the done condition for each
task (specs + docs + history entry). If a task needs a new runtime dependency,
stop — that requires an ADR and operator approval.

## Phase 5 — Implement

Follow the hard rules in [AGENTS.md](../../AGENTS.md): Ruby >= 3.0 syntax,
`frozen_string_literal: true`, exceptions over silent failure, closed
request / open response semantics, explicit top-level constant scoping inside
`Contractful::Request`. Write the failing spec first for bug fixes, then make
it pass. Keep generated and hand-written code distinguishable: contract
methods come from `define_method` in one place
(`Contract::ClassMethods#__define_contract_methods`), never from ad-hoc
`eval`.

## Phase 6 — Verify

```sh
mise exec -- bundle exec rake spec:unit
mise exec -- bundle exec rake spec:integration
mise exec -- gem build contractful.gemspec && rm contractful-*.gem
mise exec -- gem build contractful.windows.gemspec && rm contractful-*.gem
```

Report the actual counts (`N examples, M failures`). Never claim a run that
did not happen. The gemspec builds catch packaging mistakes (missing files,
broken gemspec eval) that specs cannot see.

## Phase 7 — Review

Self-review the full diff before pushing, checking for: unintended
reformatting; debug leftovers (`puts`, `binding.pry`, commented code);
secrets or credentials in fixtures or examples; exception paths that swallow
errors; frozen-string violations; behavior changes not covered by specs;
public-surface changes not reflected in README/API.md/history.md.

## Phase 8 — Deliver

Update `history.md` (user-facing changes), README and docs, then commit and
push following the one-feature-one-commit cadence. Update the PR body when
the branch maps to an open PR (PR #2 for the contract-first series). The
completion report states: what changed, which requirements moved status,
test counts, gemspec build results, and any assumptions or follow-ups.

## Autonomy bounds

An agent may act autonomously for: bug fixes, feature additions on a feature
branch with a green suite, documentation, and test improvements. It must stop
and obtain operator approval for: releasing or tagging versions, pushing gems
to RubyGems, adding or removing runtime dependencies, breaking public API
changes, editing CI authentication or permissions, force-pushing, and any
operation that touches secrets.

## Completion report template

```text
Feature/fix: <one line>
Branch/commit: <sha>
Requirements updated: <REQ-IDs and new status>
Specs: <unit> unit, <integration> integration — all green
Gemspecs: both build contractful <version>
Docs updated: <list>
Assumptions made: <list or "none">
Follow-ups: <list or "none">
```
