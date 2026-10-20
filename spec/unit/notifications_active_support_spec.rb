# frozen_string_literal: true

# Specs for the optional ActiveSupport::Notifications bridge. The bridge
# subscribes to the hub exactly once per process (require is a no-op on
# reload), so examples that clear! the hub re-load the file to re-install
# the bridge first.
#
# activesupport (~> 8.0), the test dependency that exercises the bridge,
# installs only on Ruby >= 3.2 (see Gemfile); on older Rubies this file
# defines no examples at all rather than failing to load.
require_relative '../spec_helper'

if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.2')
  require 'contractful/notifications/active_support'

  RSpec.describe 'contractful/notifications/active_support' do
    # The bridge subscribes at load time; sibling spec files clear! the hub in
    # their after hooks (and RSpec loads every file before running any), so
    # re-install the bridge before each example here.
    before do
      Contractful::Notifications.clear!
      load File.expand_path('../../lib/contractful/notifications/active_support.rb', __dir__)
    end

    after { Contractful::Notifications.clear! }

    it 'forwards hub events to ActiveSupport::Notifications' do
      received = []
      as_sub = ActiveSupport::Notifications.subscribe(/^contractful\./) do |*args|
        received << ActiveSupport::Notifications::Event.new(*args)
      end

      Contractful::Notifications.post('request', method: :get, url: 'https://api.test/x', attempt: 1)

      expect(received.size).to eq 1
      expect(received.first.name).to eq 'contractful.request'
      expect(received.first.payload).to include(method: :get, url: 'https://api.test/x', attempt: 1)
    ensure
      ActiveSupport::Notifications.unsubscribe(as_sub) if as_sub
    end

    it 'posts through the hub exactly once per event (no duplicate bridge subscriptions)' do
      count = 0
      as_sub = ActiveSupport::Notifications.subscribe(/^contractful\./) { count += 1 }

      Contractful::Notifications.post('response', method: :get, url: 'https://api.test/y', status: 200)

      expect(count).to eq 1
    ensure
      ActiveSupport::Notifications.unsubscribe(as_sub) if as_sub
      Contractful::Notifications.clear!
    end
  end
end
