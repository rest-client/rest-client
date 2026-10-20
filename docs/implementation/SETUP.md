# SETUP — development environment and local workflow

The reference environment for this repository has **no system Ruby**: Ruby
comes from [mise](https://mise.jdx.dev/), installed at
`~/.local/bin/mise`, with Ruby 4.0.7 as the current verification version.
All commands below assume that environment; adapt paths for your own.

## Prerequisites

- git
- Ruby >= 3.0 (the suite is verified on 4.0.x via mise; CI covers
  3.0, 3.1, 3.2, 3.3, 3.4, 4.0 and experimental `ruby-head`)
- Bundler

## Initial setup

```sh
git clone https://github.com/shubhamtaywade82/contractful.git
cd contractful

# with mise (reference environment)
export PATH="$HOME/.local/bin:$PATH"
mise install ruby@4.0.7          # if not already present

gem install bundler              # under mise: mise exec -- gem install bundler
bundle install
```

`bundle install` resolves the dev dependencies from
`contractful.gemspec`: rspec ~> 3.13, webmock >= 3.19 < 5, pry ~> 0.14,
rdoc >= 6.0. There are no other setup steps — no database, no services, no
environment variables required to run the offline suite.

## Running the suites

```sh
bundle exec rake spec:unit         # spec/unit/** (includes spec/unit/contract/)
bundle exec rake spec:integration  # spec/integration — includes live httpbin.org specs
bundle exec rake spec              # everything (default task)
bundle exec rake doc               # specdoc dry-run listing
```

The unit suite is fully offline. The integration suite includes a small
live component (`spec/integration/httpbin_spec.rb`, which disables WebMock
and talks to https://httpbin.org) — that is intentional and CI runs it too;
if httpbin.org is unreachable, those specific examples fail without
indicating a code problem.

## Verifying packaging

```sh
gem build contractful.gemspec          # → contractful-<version>.gem
gem build contractful.windows.gemspec  # → contractful-<version>-x64-mingw-ucrt.gem
rm -f contractful-*.gem                # artifacts are never committed
```

## Smoke-testing a local build against the real world

```sh
ruby -Ilib -e 'require "contractful";
  r = Contractful.get("https://httpbin.org/get")
  puts r.code, r.headers[:content_type]'
```

Or exercising the contract layer live:

```ruby
require 'contractful'

class Httpbin
  include Contractful::Contract
  base 'https://httpbin.org'

  contract :get_any, 'GET /get' do
    param :trace, String
    responds 200, type: Hash
    response_field :url, :string, required: true
  end
end

puts Httpbin.new.get_any(trace: 'setup-check').body
```

## Environment variables

| Variable | Purpose |
| --- | --- |
| `CONTRACTFUL_LOG` | Route contractful's own logging to `stdout`/`stderr` while debugging |
| `HTTPBIN_URL` | Override the live-spec target (proxy-aware environments) |
| `GITHUB_TOKEN` / operator-provided token file | Push access only; never committed, never embedded in the remote URL permanently |

## Windows

Development on Windows uses the `contractful-windows` platform gem
(`ffi`-based root certificate store, `x64-mingw-ucrt`); the specs under
`spec/unit/windows/` cover the certificate loading. Building the Windows
gem on Linux works via `gem build contractful.windows.gemspec` (it is a
platform gem, not a cross-compiled binary).

## Troubleshooting

See [docs/operations/RUNBOOK.md](../operations/RUNBOOK.md) for the
symptom → diagnosis → fix tables (SSL verification failures, timeout
tuning, redirect loops, proxy issues, Ruby-version mismatches).
