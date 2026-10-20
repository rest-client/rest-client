# Contributing to contractful

Thank you for helping keep this gem alive. This document covers the human
workflow; AI coding agents must additionally follow [AGENTS.md](AGENTS.md).

## Development setup

See [docs/implementation/SETUP.md](docs/implementation/SETUP.md) for the
full, tested instructions. The short version:

```sh
git clone https://github.com/shubhamtaywade82/contractful.git
cd contractful
# Ruby >= 3.0 required; the project is verified on Ruby 4.0.x via mise
gem install bundler
bundle install
bundle exec rake spec:unit
bundle exec rake spec:integration
```

The integration suite is offline (WebMock); it never touches the network.
There is also a small set of live specs against httpbin.org that maintainers
run manually before releases.

## Branching and pull requests

- `master` is always releasable: green suite, both gemspecs build.
- Open feature branches and pull requests for anything non-trivial. The
  modernization itself landed as PR #1, and the contract-first layer as
  PR #2 — both reviewed and merged by the maintainer.
- Keep PRs focused. A PR that changes behavior should come with specs; a PR
  that changes public behavior should come with README/history updates.

## Commit style

Imperative mood, conventional prefixes, one concern per commit:

```text
feat: add pagination contracts with metaprogrammed page enumerators
fix: retry loop no longer catches Contractful::Exception as ::Exception
docs: add threat model and quality gates
test: cover UnknownParam in strict mode
Release 0.1.0: closed requests, open responses, auth, idempotency, ...
```

When implementing a series of features, land them one at a time — each
feature gets its own commit (and push) once its specs are green.

## Code standards

- Ruby >= 3.0 syntax; `frozen_string_literal: true` in every file.
- Exceptions over silent failure: raise precise errors, attach the response
  where one exists (`Exception#response`, `UnexpectedResponse#response`).
- No new runtime dependency without an Architecture Decision Record in
  `docs/adr/` explaining the need, the alternatives and the cost.
- Public API changes must be reflected in `README.md` and `API.md`, and
  recorded in `history.md`.

## Testing expectations

- Every bug fix ships with a spec that fails without the fix.
- Every feature ships with unit specs; contract features live under
  `spec/unit/contract/`.
- Run the full unit + integration suites before pushing, and report real
  counts (for example: `343 examples, 0 failures`). Never report a run you
  did not perform.

## Reporting bugs

Open a GitHub issue with:

1. Ruby version (`ruby -v`) and gem version (`Contractful.version`).
2. A minimal redacted reproduction — **scrub tokens, cookies and URLs with
   credentials** before posting.
3. Expected vs actual behavior, full exception class and message.

## Reporting security issues

Do **not** open a public issue for security problems (credential handling,
TLS verification, header injection, dependency vulnerabilities). See
[docs/security/THREAT_MODEL.md](docs/security/THREAT_MODEL.md) for the model
and use a private channel: contact the maintainer through the repository
owner profile. Fixes are released on the normal cadence once a patch exists.

## License

By contributing you agree that your contributions are licensed under the
MIT License (see [LICENSE](LICENSE)).
