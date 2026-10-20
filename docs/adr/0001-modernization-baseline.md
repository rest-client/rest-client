# ADR 0001 — Modernization baseline: supported Ruby range and CI

- **Status:** Accepted (2026-10, shipped as 2.2.0 via PR #1)
- **Context:** upstream contractful archived 2019, last release 2.1.0,
  unbuildable/untestable on Ruby 3.x/4.x
- **Deciders:** repository maintainer + implementing agent

## Context

The upstream gem was archived with years-old tooling: webmock ~> 2.0,
rubocop 0.49, rdoc < 6.0, a dead Travis CI configuration, and internal code
carrying Ruby 2.0-era compatibility shims. Ruby 4.0 removed the `base64`
default gem and tightened OpenSSL version-symbol handling, so the gem could
not even be exercised on current Rubies. Users of long-lived applications
needed a maintained fork, not a rewrite.

## Decision

1. **Require Ruby >= 3.0** (`required_ruby_version`) and drop all pre-3.0
   compatibility code rather than preserving it. The 2.0-era header-parsing
   shims in `utils.rb` (~90 lines) were deleted outright.
2. **Test the whole modern range in CI:** GitHub Actions matrix
   3.0 / 3.1 / 3.2 / 3.3 / 3.4 / 4.0 plus an experimental `ruby-head` job,
   with `permissions: contents: read`. Travis config deleted.
3. **Adapt to Ruby 4.0 realities inside the library** rather than pinning
   old behavior:
   - SSL versions pass through `normalize_ssl_version`, mapping
     `:TLSv1_2`-style symbols, `:TLS1_2`-style symbols and strings to the
     OpenSSL constants Ruby 4.0 accepts.
   - Empty-hostname URIs are rejected (Ruby 3.4+ returns `''` where older
     Rubies returned `nil` — both are invalid).
   - The test suite uses `String#unpack1('m')` instead of the removed
     `base64` default gem.
4. **Modernize dev tooling only as far as needed** (rspec ~> 3.13, webmock
   >= 3.19 < 5, rdoc >= 6.0); no linter was reintroduced in 2.2 — quality is
   gated by the spec suite (see QUALITY_GATES.md).
5. **Refresh rotted TLS fixtures** (DigiCert 2019 → ISRG Root X1) so live
   SSL specs verify against current chains.

## Alternatives considered

- **Fork with wide compatibility (Ruby 2.x kept):** rejected — doubles the
  test matrix and preserves code paths nothing modern exercises.
- **Full rewrite of the client core:** rejected — the value of contractful
  is its stable, familiar API; the core pipeline was sound.
- **freeze upstream / wait:** rejected — the archive means no movement.

## Consequences

- Positive: one supported range, real CI signal, gem builds on current
  RubyGems, security-relevant TLS behavior testable.
- Costs: drop-in for Ruby 2.x applications is gone by declaration (they pin
  1.x/2.1 anyway); new Ruby removals surface as matrix failures to be fixed
  forward, which is the point.
