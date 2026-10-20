# DELIVERY — versioning, CI, releases and rollback

How changes travel from a green branch to a published gem, and how to back
a bad release out. The cadence follows the repository's established
discipline: small green commits, one feature at a time, PRs for series of
work (PR #1 modernization, PR #2 contract-first), tags after merge.

## Versioning

- **Semantic versioning.** Bug fixes bump patch; new backwards-compatible
  features bump minor; anything that breaks the surface documented in
  [API.md](../../API.md) bumps major.
- `lib/contractful/version.rb` is the single source of truth
  (`Contractful::VERSION`); both gemspecs derive from it.
- `history.md` carries one section per release; a release commit without a
  matching history section is incomplete (gate G8). The current series:
  2.2.0 modernization → 2.3.0 retries/pooling/json → 2.4.0 contract core →
  2.5.0 closed/open semantics, auth, idempotency, pagination, rate limits.

## Branching model

- `master` is releasable at all times: green suite, building gemspecs.
- Work lands via feature branches and PRs for multi-commit series, or
  direct small green commits for single fixes. The two big series both went
  through PRs (PR #1, PR #2) reviewed and merged by the maintainer.
- Release series that live on a branch (as 2.4/2.5 did on
  `feature/contract-first`) are tagged **after** the PR merges: `v2.4.0`,
  `v2.5.0` on master, not on the feature branch.

## CI in delivery

Every push runs the matrix (Ruby 3.0–4.0 unit + integration specs,
experimental `ruby-head`); see QUALITY_GATES.md G1/G2. A PR is mergeable
only with a green matrix. `ruby-head` failures are warnings to investigate,
not merge blockers.

## Release checklist (maintainer)

1. Confirm the merge landed and CI is green on `master`.
2. Bump `Contractful::VERSION` (if not already on a release commit) and
   finalize the `history.md` section.
3. Build both gems: `gem build contractful.gemspec` and
   `gem build contractful.windows.gemspec` (or `rake all:build`).
4. Release QA per TESTING.md: full `rake spec`, live httpbin spot-check,
   install the built gem in a scratch gemset, run README smoke snippets.
5. Commit the release (`Release X.Y.Z: <one-line summary>`), push, tag
   `vX.Y.Z`, push the tag.
6. Publish: `gem push contractful-X.Y.Z.gem` and the Windows platform gem
   (`rake all:release` automates build+tag+push). **Publication is
   maintainer-only** — RubyGems credentials and MFA
   (`rubygems_mfa_required`) are never held by automated agents
   (AGENT_TOOL_POLICY.md).
7. Verify the release page on rubygems.org picks up metadata (changelog
   URI, source code URI) from the gemspec.

## Rollback

- **Bad published gem:** yank (`gem yank contractful -v X.Y.Z`) removes it
  from resolution — RubyGems treats yanking as exceptional, so pair it with
  a `history.md` postmortem note. Prefer shipping a fix release; yank only
  for security/corruption-class failures.
- **Bad commit on master:** revert with a normal commit (never rewrite
  published history). If the revert itself needs specs, it is a fix, not a
  revert.
- **Bad tag:** delete and re-tag only before anything consumes the tag
  (post-publication tags are immutable in practice).
- **Hotfix path:** branch from the release tag, fix with a failing-then-
  passing spec, release as X.Y.Z+1, merge forward to master.

## Post-merge bookkeeping

Update the requirements matrix statuses
(docs/requirements/REQUIREMENTS.md), close or update the PR-tracking
comment threads, and record the merge + tag in the session work log. The
next session's bootstrap (AGENT_WORKFLOWS.md Phase 0) reads exactly that
state, so keep it truthful.
