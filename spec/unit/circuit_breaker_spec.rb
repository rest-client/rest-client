# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Contractful::CircuitBreaker do
  let(:breaker) do
    described_class.new('https://api.test:443', threshold: 3, cooldown: 0.05)
  end

  describe 'initialization' do
    it 'rejects a non-positive threshold' do
      expect { described_class.new('k', threshold: 0) }.to raise_error(ArgumentError, /threshold/)
    end

    it 'rejects a non-positive cooldown' do
      expect { described_class.new('k', cooldown: -1) }.to raise_error(ArgumentError, /cooldown/)
    end
  end

  describe 'state machine' do
    it 'lets a subscriber inspect the breaker without deadlocking' do
      observed = []
      b = described_class.new('https://notified.test:443', threshold: 1, cooldown: 60)
      unsubscribe = Contractful::Notifications.subscribe do |event|
        observed << [event[:payload][:state], b.state]
      end
      begin
        b.record_failure
      ensure
        unsubscribe.call
        Contractful::Notifications.clear!
      end

      expect(observed).to eq [%i[open open]]
    end

    it 'stays closed under the threshold and opens at it' do
      expect(breaker.state).to eq :closed
      2.times { breaker.record_failure }
      expect(breaker.state).to eq :closed

      expect { breaker.check! }.not_to raise_error

      breaker.record_failure
      expect(breaker.state).to eq :open
      expect { breaker.check! }.to raise_error(Contractful::CircuitOpenError, %r{circuit open for https://api.test:443})
    end

    it 'transitions to half-open after the cooldown and closes on probe success' do
      3.times { breaker.record_failure }
      sleep 0.06
      expect(breaker.state).to eq :half_open
      expect { breaker.check! }.not_to raise_error

      breaker.record_success
      expect(breaker.state).to eq :closed
      expect { breaker.check! }.not_to raise_error
    end

    it 're-opens immediately when a half-open probe fails' do
      3.times { breaker.record_failure }
      sleep 0.06
      expect(breaker.state).to eq :half_open

      breaker.record_failure
      expect(breaker.state).to eq :open
    end

    it 'reports the remaining cooldown in the error message' do
      b = described_class.new('k', threshold: 1, cooldown: 5)
      b.record_failure
      expect { b.check! }.to raise_error(Contractful::CircuitOpenError, /retry after \d+\.\d+s/)
    end

    it 'resets the failure count when the circuit closes' do
      2.times { breaker.record_failure }
      breaker.record_success
      breaker.record_failure
      expect(breaker.state).to eq :closed
    end
  end

  describe '#record_response' do
    it 'counts retryable statuses as failures and client errors as success' do
      allow(Contractful::Exceptions).to receive(:retryable?).and_call_original
      breaker.record_response(instance_double(Contractful::Response, code: 503))
      breaker.record_response(instance_double(Contractful::Response, code: 404))
      expect(breaker.state).to eq :closed

      breaker.record_response(instance_double(Contractful::Response, code: 503))
      breaker.record_response(instance_double(Contractful::Response, code: 502))
      breaker.record_response(instance_double(Contractful::Response, code: 429))
      expect(breaker.state).to eq :open
    end
  end

  describe 'notifications' do
    it 'posts a circuit event on every state transition' do
      events = []
      Contractful::Notifications.subscribe { |e| events << e }

      b = described_class.new('k', threshold: 1, cooldown: 0.01)
      b.record_failure
      sleep 0.02
      b.check!
      b.record_success

      transitions = events.select { |e| e[:name] == 'circuit' }.map { |e| [e[:payload][:from], e[:payload][:state]] }
      expect(transitions).to eq [%i[closed open], %i[open half_open], %i[half_open closed]]
    end
  end

  describe 'registry' do
    after { described_class.registry.clear! }

    it 'returns the same breaker per scheme/host/port key' do
      uri = URI('https://api.test:443/x')
      a = described_class.registry.breaker_for(uri)
      b = described_class.registry.breaker_for(URI('https://api.test:443/y'))
      expect(a).to be b
      expect(described_class.registry.size).to eq 1
    end

    it 'keys different hosts separately' do
      described_class.registry.breaker_for(URI('https://a.test:443/'))
      described_class.registry.breaker_for(URI('https://b.test:443/'))
      expect(described_class.registry.size).to eq 2
    end
  end
end

RSpec.describe 'circuit breaker end-to-end' do
  let(:url) { 'http://breaker.test:80/resource' }

  before do
    Contractful::Notifications.clear!
    Contractful::CircuitBreaker.registry.clear!
    stub_request(:get, url).to_return(status: 503)
  end

  after do
    Contractful::Notifications.clear!
    Contractful::CircuitBreaker.registry.clear!
  end

  it 'opens after threshold exhausted-retry failures and fails fast without hitting the network' do
    opts = { method: :get, url: url, max_retries: 0, breaker: { threshold: 2, cooldown: 60 } }

    2.times do
      expect { Contractful::Request.execute(**opts) }.to raise_error(Contractful::ServiceUnavailable)
    end

    WebMock.reset!
    expect { Contractful::Request.execute(**opts) }.to raise_error(Contractful::CircuitOpenError)
  end

  it 'does not open on client errors' do
    not_found_url = 'http://breaker.test:80/missing'
    stub_request(:get, not_found_url).to_return(status: 404)
    opts = {
      method: :get,
      url: not_found_url,
      max_retries: 0,
      breaker: { threshold: 2, cooldown: 60 }
    }

    2.times do
      expect { Contractful::Request.execute(**opts) }
        .to raise_error(Contractful::ResourceNotFound)
    end

    breaker = Contractful::CircuitBreaker.registry.breaker_for(URI('http://breaker.test:80'))
    expect(breaker.state).to eq :closed
    expect { Contractful::Request.execute(**opts) }
      .to raise_error(Contractful::ResourceNotFound)
  end

  it 'ignores an unknown response instead of treating it as success' do
    unknown_breaker = Contractful::CircuitBreaker.new('https://unknown.test:443', threshold: 1, cooldown: 60)
    unknown_breaker.record_failure
    expect(unknown_breaker.state).to eq :open

    unknown_breaker.record_response(nil)

    expect(unknown_breaker.state).to eq :open
  end

  it 'is opt-in: without breaker no state accumulates' do
    3.times do
      expect { Contractful::Request.execute(method: :get, url: url) }
        .to raise_error(Contractful::ServiceUnavailable)
    end
    expect(Contractful::CircuitBreaker.registry.size).to eq 0
  end

  it 'passes through the contract layer as _breaker' do
    client = Class.new do
      include Contractful::Contract

      base 'http://breaker.test:80'
      contract :ping, 'GET /resource' do
        responds 200, 503
      end
    end.new

    2.times { client.ping(_breaker: { threshold: 2, cooldown: 60 }, _max_retries: 0) }
    expect(Contractful::CircuitBreaker.registry.size).to eq 1
    expect { client.ping(_breaker: { threshold: 2, cooldown: 60 }) }
      .to raise_error(Contractful::CircuitOpenError)
  end
end
