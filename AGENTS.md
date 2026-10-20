# AGENTS.md — rules for AI coding agents

Instructions for AI coding agents (Claude Code, Cursor, Aider, and similar)
working in this repository. Human contributors should read
[CONTRIBUTING.md](CONTRIBUTING.md) instead; everything here applies to them
too, but this file is written for agents executing work autonomously.

## What this project is

`contractful` is a simple HTTP and REST client for Ruby, kept alive after the
upstream gem was archived in 2019. This fork supports Ruby 3.0 through 4.0,
ships a modern CI matrix, and adds a **contract-first architecture layer**
(`Contractful::Contract`) built on heavy metaprogramming: you declare the HTTP
shape of an API and the gem generates the client methods, validation and
introspection. Current version lives in `lib/contractful/version.rb`; every
user-facing change is recorded in `history.md`.

## Reading order

Read these before writing any code. Later documents assume earlier ones.

| Order | Document | What it gives you |
| ----- | -------- | ----------------- |
| 1 | [README.md](README.md) | Public behavior, runnable examples |
| 2 | [PRD.md](PRD.md) | Product goals, feature requirements, non-goals |
| 3 | [ARCHITECTURE.md](ARCHITECTURE.md) | Layers, module map, request lifecycle |
| 4 | [API.md](API.md) | The exact public surface and its stability rules |
| 5 | [docs/engineering/TESTING.md](docs/engineering/TESTING.md) | How specs are organized and run |
| 6 | [docs/agents/AGENT_WORKFLOWS.md](docs/agents/AGENT_WORKFLOWS.md) | The phase-by-phase execution workflow |
| 7 | [docs/security/AGENT_TOOL_POLICY.md](docs/security/AGENT_TOOL_POLICY.md) | What an agent may and may not do here |

## Hard engineering rules

These rules are not negotiable; they exist because each one has already
caused a real bug in this codebase.

1. **Ruby >= 3.0 syntax only.** The gemspec declares
   `required_ruby_version >= 3.0` and CI tests 3.0–4.0 plus `ruby-head`.
   Never use syntax or stdlib behavior newer than 3.0, and never add
   version-conditional code without a spec that pins the behavior on both
   sides of the boundary.
2. **`frozen_string_literal: true`** at the top of every file under `lib/`
   and `spec/`.
3. **Ruby 4.0 compatibility traps** (all verified on Ruby 4.0.7):
   - The `base64` default gem was removed — never `require 'base64'`; use
     `String#unpack1('m')` for the decoding the test suite needs.
   - `URI.parse('http:///').hostname` returns `''` on Ruby 3.4+ (was `nil`);
     any hostname check must treat both as invalid.
   - Ruby 4.0's OpenSSL rejects the `:TLSv1_2` symbol form. Always route SSL
     version configuration through `Contractful::Request#normalize_ssl_version`
     instead of passing raw symbols to `Net::HTTP`.
   - rspec-mocks treats a bare `.with(hash)` as keyword arguments on modern
     Ruby; wrap expected hashes in explicit braces: `.with({ payload: ... })`.
4. **Lexical constant shadowing.** Inside `Contractful::Request`, a bare
   `Exception` resolves to `Contractful::Exception` and `Timeout` to
   `Contractful::Exceptions::Timeout`. Scope top-level constants explicitly
   (`::Exception`, `::Timeout::Error`) when you mean the Ruby built-ins.
5. **No new runtime dependency without an ADR** in `docs/adr/`. The runtime
   dependency set (`http-accept`, `http-cookie`, `mime-types`, `netrc`) is a
   deliberate, small surface. The contract layer deliberately adds **zero**
   runtime dependencies.
6. **Exceptions over silent failure.** A misparsed response is worse than a
   raised error. Violations raise precise errors (`Contractful::Contract::*`,
   `Contractful::Exception` subclasses) instead of being swallowed,
   logged-and-ignored, or converted to `nil`.
7. **Closed requests, open responses.** Request-side validation rejects bad
   input *before* any network traffic. Response-side validation binds only
   declared required fields and types; unknown fields are data, not errors.
   Never "fix" a violation by silently coercing data.

## Testing discipline

- Run `mise exec -- bundle exec rake spec:unit` and
  `mise exec -- bundle exec rake spec:integration` before every push. Report
  the actual example/failure counts; **never claim tests pass without having
  run them.**
- Spec files mirror `lib/` paths. Contract specs live in
  `spec/unit/contract/`. Integration specs are offline (WebMock); live
  network specs exist separately and must never be required for CI to pass.
- WebMock stubs with a bare URL only match query-less requests. When a
  contract declares defaults that end up in the query string, stub with
  `hash_including`, not an exact hash.
- New `lib/` code without a spec is an incomplete change. Bug fixes need a
  failing-then-passing spec that demonstrates the bug.

## Git discipline

- Branches: work on a feature branch and open a PR (this is the established
  pattern of this repo), or commit directly when the change is small and the
  suite is green. `master` must always be releasable.
- Commits: one concern per commit, imperative subject, conventional prefix
  (`feat:`, `fix:`, `docs:`, `test:`, `chore:`, or `Release X.Y.Z:`).
  Implement features one at a time — commit and push when each one is
  complete.
- Never force-push shared branches, never rewrite published history, never
  skip CI on purpose.
- **Secrets:** credentials come from the operator (for example a token file
  outside the repository). Never commit tokens; never leave an authenticated
  remote URL configured after pushing; never echo secrets into logs, specs
  or fixtures.

## Definition of done

A change is done when all of the following hold:

- [ ] Full unit + integration suite green (counts reported honestly)
- [ ] Both gemspecs still build (`contractful.gemspec`,
      `contractful.windows.gemspec`)
- [ ] `history.md` updated for user-facing changes
- [ ] README / docs updated when public behavior changes
- [ ] No secrets, no debug leftovers, no unrelated reformatting in the diff

## Where things live

| Path | Contents |
| ---- | -------- |
| `lib/contractful/` | Runtime code (`request.rb`, `contract/`, `connection_pool.rb`, ...) |
| `spec/unit`, `spec/integration` | Specs mirroring `lib/` |
| `docs/` | Requirements, ADRs, engineering, security, operations, agent guides |
| `history.md` | Release notes, one section per version |
| `worklog.md` (operator workspace, not committed) | Cross-session work records |
