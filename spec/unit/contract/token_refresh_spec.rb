# frozen_string_literal: true

require_relative '../../spec_helper'

# Token-provider auth: Bearer credentials from an object that can refresh
# itself, with one-flight refresh-on-401 coordination.
RSpec.describe Contractful::Contract::TokenRefresh do
  let(:provider) do
    Class.new do
      def initialize
        @token = 'stale'
        @refreshes = 0
      end
      attr_reader :refreshes

      attr_reader :token

      def refresh
        @refreshes += 1
        @token = "fresh-#{@refreshes}"
      end
    end.new
  end

  describe '.refresh' do
    it 'invokes refresh and posts a token_refresh notification' do
      events = []
      Contractful::Notifications.subscribe { |e| events << e }

      token = described_class.refresh(provider)

      expect(token).to eq 'fresh-1'
      expect(provider.refreshes).to eq 1
      expect(events.map { |e| e[:name] }).to include('token_refresh')
      expect(events.find { |e| e[:name] == 'token_refresh' }[:payload][:provider]).to eq provider.class.name
    end

    it 'never runs two refreshes for one provider concurrently' do
      concurrent = 0
      max_concurrent = 0
      gate = Mutex.new
      slow = Class.new do
        define_method(:token) { 't' }
        define_method(:refresh) do
          gate.synchronize do
            concurrent += 1
            max_concurrent = [max_concurrent, concurrent].max
          end
          sleep 0.02
          gate.synchronize { concurrent -= 1 }
          'refreshed'
        end
        define_method(:max_seen) { max_concurrent }
      end.new

      5.times.map { Thread.new { described_class.refresh(slow) } }.each(&:join)

      expect(slow.max_seen).to eq 1
    ensure
      described_class.clear!
    end
  end
end

RSpec.describe 'refresh-on-401 end-to-end' do
  let(:provider) do
    Class.new do
      def initialize
        @token = 'stale'
        @refreshes = 0
      end
      attr_reader :refreshes

      attr_reader :token

      def refresh
        @refreshes += 1
        @token = "fresh-#{@refreshes}"
      end
    end.new
  end

  let(:client) do
    prov = provider
    Class.new do
      include Contractful::Contract

      base 'http://auth.test'
      auth token_provider: prov
      contract :get_data, 'GET /data' do
        responds 200, 401
      end
    end.new
  end

  after { Contractful::Contract::TokenRefresh.clear! }

  it 'rejects a provider that cannot refresh at definition time' do
    expect do
      Class.new do
        include Contractful::Contract

        base 'http://x.test'
        auth token_provider: 'not-a-provider'
      end
    end.to raise_error(Contractful::Contract::InvalidDefinition, /token_provider.*#token and #refresh/)
  end

  it 'refreshes once and retries with the fresh token on a 401' do
    stub_request(:get, 'http://auth.test/data')
      .with(headers: { 'Authorization' => 'Bearer stale' }).to_return(status: 401)
    stub_request(:get, 'http://auth.test/data')
      .with(headers: { 'Authorization' => 'Bearer fresh-1' }).to_return(body: 'ok')

    response = client.get_data

    expect(response.code).to eq 200
    expect(provider.refreshes).to eq 1
  end

  it 'does not refresh on success' do
    stub_request(:get, 'http://auth.test/data').to_return(body: 'ok')

    expect(client.get_data.code).to eq 200
    expect(provider.refreshes).to eq 0
  end

  it 'returns the second 401 as a normal response after one refresh attempt' do
    stub_request(:get, 'http://auth.test/data')
      .with(headers: { 'Authorization' => 'Bearer stale' }).to_return(status: 401)
    stub_request(:get, 'http://auth.test/data')
      .with(headers: { 'Authorization' => 'Bearer fresh-1' }).to_return(status: 401)

    expect(client.get_data.code).to eq 401
    expect(provider.refreshes).to eq 1
  end

  it 'refreshes only once across the retry (no loop on repeated 401s)' do
    stub_request(:get, 'http://auth.test/data').to_return(status: 401)

    expect(client.get_data.code).to eq 401
    expect(provider.refreshes).to eq 1
    expect(a_request(:get, 'http://auth.test/data')).to have_been_made.times(2)
  end

  context 'when the contract does not declare 401' do
    let(:client) do
      prov = provider
      Class.new do
        include Contractful::Contract

        base 'http://auth.test'
        auth token_provider: prov
        contract :get_data, 'GET /data' do
          responds 200
        end
      end.new
    end

    it 'still refreshes and retries once' do
      stub_request(:get, 'http://auth.test/data')
        .with(headers: { 'Authorization' => 'Bearer stale' }).to_return(status: 401)
      stub_request(:get, 'http://auth.test/data')
        .with(headers: { 'Authorization' => 'Bearer fresh-1' }).to_return(body: 'ok')

      response = client.get_data

      expect(response.code).to eq 200
      expect(provider.refreshes).to eq 1
    end
  end

  it 'does not refresh when the contract opts out of auth' do
    prov = provider
    opt_out_client = Class.new do
      include Contractful::Contract

      base 'http://auth.test'
      auth token_provider: prov
      contract :get_data, 'GET /data' do
        auth false
        responds 200, 401
      end
    end.new

    stub_request(:get, 'http://auth.test/data').to_return(status: 401)

    expect(opt_out_client.get_data.code).to eq 401
    expect(provider.refreshes).to eq 0
    expect(a_request(:get, 'http://auth.test/data')).to have_been_made.once
  end
end
