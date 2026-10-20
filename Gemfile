source 'https://rubygems.org'

# The windows gemspec is only used by `gem build` when releasing platform
# specific gems (see Rakefile); bundler always uses the main gemspec here.
gemspec

group :test do
  gem 'rake'
  # Coverage measurement and CI gate (>= 95% line coverage on lib/).
  # Loaded at the top of spec/spec_helper.rb, before any library code.
  gem 'simplecov', '~> 0.22', require: false
  # Test-only: exercises the optional ActiveSupport::Notifications bridge.
  # ActiveSupport 8 requires Ruby >= 3.2; on older Rubies the bridge specs
  # skip themselves (see spec/unit/notifications_active_support_spec.rb) —
  # the bridge itself stays an optional integration, never a runtime
  # dependency, so it is fine to not exercise it there.
  gem 'activesupport', '~> 8.0', require: false if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.2')
end

group :development, :test do
  # API documentation rendering (`yard doc`, `yard stats`). require: false —
  # nothing in the runtime or test suite loads it.
  gem 'redcarpet', '~> 3.6', require: false
  gem 'yard', '~> 0.9', require: false

  # Static analysis baseline (see .rubocop.yml for the adoption strategy).
  # require: false - nothing in the runtime loads these; the Rakefile task
  # and CI lint job require them explicitly.
  # Patch-level constraints (not ~> 1.92) because Gemfile.lock is not
  # committed: newer RuboCop minors can enable new cops, which would break
  # the lint baseline without any change to this repository.
  gem 'rubocop', '~> 1.92.0', require: false
  gem 'rubocop-rspec', '~> 3.10.0', require: false
end
