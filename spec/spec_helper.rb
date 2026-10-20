# frozen_string_literal: true

# SimpleCov must start before any library code is loaded so every
# lib/contractful definition is tracked. Coverage is a CI quality gate
# (see docs/engineering/QUALITY_GATES.md): the unit suite refuses to pass
# below the configured threshold.
require 'simplecov'

SimpleCov.start do
  enable_coverage :line
  root File.expand_path('..', __dir__)

  add_filter '/spec/'
  add_filter '/bin/'
  # Platform-specific code lives behind `if Contractful::Platform.windows?`
  # guards and can never execute on the Linux CI runners.
  add_filter '/lib/contractful/windows'
  # Bundler evaluates the gemspec (which require_relative's version.rb) while
  # setting up `bundle exec` — before any coverage tracer can attach — so
  # this file can never register execution. It is fully exercised at load
  # time; filtering it is measurement hygiene, not a coverage dodge.
  add_filter '/lib/contractful/version.rb'
  # The optional ActiveSupport bridge is exercised by the test bundle only
  # where activesupport (~> 8.0) can install — Ruby >= 3.2 (see Gemfile).
  # On older Rubies the file would sit at 0% and sink the gate through no
  # fault of its own; where it loads, it counts toward the gate in full.
  add_filter '/lib/contractful/notifications/active_support' if
    Gem::Version.new(RUBY_VERSION) < Gem::Version.new('3.2')

  track_files 'lib/**/*.rb'

  # Distinct command names keep the unit and integration resultsets from
  # merging into one another (they exercise different slices of lib/).
  command_name "RSpec #{ENV.fetch('COVERAGE_SUITE', 'unit')}"

  minimum_coverage line: 95.0 if ENV['COVERAGE_GATE']
end

require 'webmock/rspec'
require 'contractful'

require_relative 'helpers'

# See http://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration
RSpec.configure do |config|
  config.raise_errors_for_deprecations!

  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = 'random'

  # always run with ruby warnings enabled
  # TODO: figure out why this is so obscenely noisy (rspec bug?)
  # config.warnings = true

  # add helpers
  config.include Helpers, :include_helpers

  # Live-network specs are opt-in; CI never depends on external hosts.
  config.filter_run_excluding :live unless ENV['LIVE_HTTP_TESTS']

  config.mock_with :rspec do |mocks|
    mocks.yield_receiver_to_any_instance_implementation_blocks = true
  end

  # Contractful.log is process-global state, and several logging specs assign
  # it directly (`log = Contractful.log = []`). Under RSpec's random ordering
  # such an assignment would leak into unrelated examples that never enabled
  # logging: unit CI observed request2_spec's "does not retry when the
  # payload cannot be rewound" dying with NoMethodError on a leaked logger,
  # and resource specs receiving a leaked log array as their expected
  # `:log => nil` option. Reset it after every example so examples stay
  # order-independent regardless of which logging specs ran before them.
  config.after do
    Contractful.log = nil
  end
end

# always run with ruby warnings enabled (see above)
$VERBOSE = true
