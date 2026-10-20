# QUALITY GATES — what must be true to merge and release

Quality gates are the difference between documenting standards and
enforcing them. Each gate below states what must be true, how it is
verified, and who enforces it (CI = automatically blocking; reviewer =
human/agent judgment at PR review; release = maintainer checklist). A gate
without an enforcer is an aspiration, not a gate — when a gate here is
marked "reviewer", treat it as a required PR checklist item, not a
suggestion.

## The gates

| # | Gate | Verification | Enforced by |
| --- | --- | --- | --- |
| G1 | Full unit + integration suites green on the Ruby 3.0–4.0 matrix | `rake spec:unit`, `rake spec:integration` in CI | CI (blocking) |
| G2 | Contract specs included in the unit run | `spec/unit/**` glob in the Rakefile (fixed 2026-10; previously skipped `spec/unit/contract/` in CI) | CI (blocking) |
| G3 | Both gemspecs build from a clean checkout | `gem build contractful.gemspec` + `gem build contractful.windows.gemspec` | Release checklist (manual) |
| G4 | New/changed `lib/` code has verifying specs; bug fixes have failing-then-passing specs | PR diff inspection | Reviewer |
| G5 | No new runtime dependency without an ADR | gemspec diff + `docs/adr/` link | Reviewer (CI can flag the gemspec diff) |
| G6 | `frozen_string_literal: true` in every touched `lib/`/`spec/` file | PR diff inspection | Reviewer |
| G7 | Public-surface changes update README, API.md and history.md | PR diff inspection | Reviewer |
| G8 | Version constant bumped and history.md section present for releases | Release commit inspection | Release checklist |
| G9 | Conventional, one-concern commits; `master` receives only green code | Commit log inspection | Reviewer |
| G10 | No secrets in diffs (tokens, cookies, credentials, internal URLs) | PR diff inspection; see THREAT_MODEL.md T8 | Reviewer (zero tolerance) |
| G11 | CI workflow keeps `permissions: contents: read` and does not gain credential movement | Workflow diff inspection | Reviewer |
| G12 | Exceptions over silent failure: no swallowed errors, no nil-conversion of unexpected responses | PR diff inspection + error-path specs | Reviewer |
| G13 | Line coverage on `lib/` stays >= 95% (measured by simplecov over the unit suite) | `rake spec:unit` — SimpleCov fails the run below the threshold | CI (blocking) |

## What CI enforces today

`.github/workflows/ci.yml` blocks merges on: unit specs (including the
contract suite), integration specs, RuboCop (pinned, safe-autocorrect only),
across Ruby 3.0/3.1/3.2/3.3/3.4/4.0, with an experimental non-blocking
`ruby-head` job. The unit job also enforces the coverage gate (G13): the
suite runs under simplecov and fails below 95% line coverage on `lib/`
(the `windows/` platform shims and `version.rb` — which Bundler evaluates
before any coverage tracer can attach — are filtered with cause documented
in `spec/spec_helper.rb`). It runs with `permissions: contents: read`.
That is the entire automated gate surface — everything else is disciplined
review, which is honest to say: this project prefers a small, sharp CI
surface plus rigorous review over a large config that nobody audits.

## What CI does not enforce (yet)

Recorded here deliberately, so nobody mistakes their absence for
impossibility:

- **Contract-breaking-change diffing:** once the planned OpenAPI import
  (REQ-N01) gives the project a machine-readable view of a client's
  contracts, a CI job can diff the previous release's contract set against
  the branch's (the oasdiff pattern) and fail on unapproved breaking
  changes. Until the DSL is the only contract format in use, that diff
  would be false precision.

## Merge criteria (summary)

A PR merges when: G1/G2 are green on the branch; the reviewer confirms
G4–G7 and G9–G12; and any gate the PR violates has an explicit, recorded
waiver in the PR (waivers are exceptional and say why). Releases
additionally require G3, G8 and the release checklist in
[DELIVERY.md](../operations/DELIVERY.md).

## Reviewer checklist (condensed)

```text
[ ] Suites green (CI badge on the PR, not memory)
[ ] Specs cover the new behavior AND its violation paths
[ ] No runtime dep changes without ADR
[ ] frozen_string_literal present in touched files
[ ] README / API.md / history.md updated if the surface changed
[ ] Commit messages conventional and atomic
[ ] Diff free of secrets, debug leftovers, unrelated churn
[ ] Error paths raise precise exceptions, attach responses
```
