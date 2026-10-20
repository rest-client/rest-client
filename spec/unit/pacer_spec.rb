# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Contractful::Pacer do
  describe 'initialization' do
    it 'rejects a non-positive limit' do
      expect { described_class.new('k', limit: 0) }.to raise_error(ArgumentError, /limit/)
    end

    it 'rejects a non-positive window' do
      expect { described_class.new('k', window: 0) }.to raise_error(ArgumentError, /window/)
    end

    it 'rejects a negative max_wait' do
      expect { described_class.new('k', max_wait: -1) }.to raise_error(ArgumentError, /max_wait/)
    end
  end

  describe '#acquire' do
    it 'admits requests below the limit and records them in the window' do
      pacer = described_class.new('k', limit: 3, window: 60)
      3.times { pacer.acquire }
      expect(pacer.pending).to eq 3
    end

    it 'raises PacingTimeout when the required wait exceeds max_wait' do
      pacer = described_class.new('k', limit: 1, window: 60, max_wait: 5)
      pacer.acquire
      expect { pacer.acquire }.to raise_error(
        Contractful::PacingTimeout,
        %r{pace limit 1/60s for k would wait 60\.0s \(max_wait 5s\)}
      )
    end

    it 'sleeps and retries when the wait fits max_wait, then admits' do
      pacer = described_class.new('k', limit: 1, window: 0.1, max_wait: 5)
      pacer.acquire
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      pacer.acquire

      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
        .to be_between(0.05, 1.0)
      expect(pacer.pending).to eq 1 # old slot expired by then
    end

    it 'posts a pace notification for every actual wait' do
      events = []
      Contractful::Notifications.subscribe { |e| events << e }

      pacer = described_class.new('k', limit: 1, window: 0.1, max_wait: 5)
      pacer.acquire
      pacer.acquire

      pace_events = events.select { |e| e[:name] == 'pace' }
      expect(pace_events.size).to eq 1
      expect(pace_events.first[:payload]).to include(key: 'k', limit: 1, window: 0.1)
    end

    it 'never sleeps when the budget is available' do
      pacer = described_class.new('k', limit: 2, window: 60)
      expect(pacer).not_to receive(:sleep)
      pacer.acquire
      pacer.acquire
    end
  end

  describe 'registry' do
    after { described_class.registry.clear! }

    it 'returns the same pacer per scheme/host/port' do
      a = described_class.registry.pacer_for(URI('https://paced.test:443/x'))
      b = described_class.registry.pacer_for(URI('https://paced.test:443/y'))
      expect(a).to be b
    end

    it 'separates hosts' do
      described_class.registry.pacer_for(URI('https://a.test:443/'))
      described_class.registry.pacer_for(URI('https://b.test:443/'))
      expect(described_class.registry.size).to eq 2
    end
  end
end

RSpec.describe 'pacing end-to-end' do
  let(:url) { 'http://paced.test:80/resource' }

  before { Contractful::Pacer.registry.clear! }
  after { Contractful::Pacer.registry.clear! }

  it 'delays the second request when the configured window is exhausted' do
    stub_request(:get, url).to_return(body: 'ok')
    pace_events = []
    Contractful::Notifications.subscribe { |e| pace_events << e if e[:name] == 'pace' }
    opts = { method: :get, url: url, pace: { limit: 1, window: 0.1, max_wait: 5 } }

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    2.times { Contractful::Request.execute(**opts) }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    expect(pace_events.size).to eq 1
    expect(elapsed).to be >= 0.05
    expect(Contractful::Pacer.registry.size).to eq 1
  end

  it 'is opt-in' do
    stub_request(:get, url).to_return(body: 'ok')
    3.times { Contractful::Request.execute(method: :get, url: url) }
    expect(Contractful::Pacer.registry.size).to eq 0
  end

  it 'passes through the contract layer as _pace' do
    stub_request(:get, url).to_return(body: 'ok')
    client = Class.new do
      include Contractful::Contract

      base 'http://paced.test:80'
      contract :ping, 'GET /resource' do
        responds 200
      end
    end.new

    client.ping(_pace: { limit: 1, window: 60 })
    expect(Contractful::Pacer.registry.size).to eq 1
  end
end
