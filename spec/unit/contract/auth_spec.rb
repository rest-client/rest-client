# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe 'Contractful::Contract auth' do
  def build_client(&block)
    Class.new do
      include Contractful::Contract

      instance_exec(&block)
    end
  end

  let(:client_class) do
    build_client do
      base 'https://api.test'

      auth bearer: 'token-123'

      contract :list_orders, 'GET /orders' do
        param :page, Integer, default: 1
      end

      contract :health, 'GET /health' do
        auth false
      end
    end
  end

  let(:client) { client_class.new }

  describe 'bearer scheme' do
    it 'sends the Authorization header' do
      stub = stub_request(:get, 'https://api.test/orders')
             .with(headers: { 'Authorization' => 'Bearer token-123' },
                   query: hash_including('page' => '1'))

      client.list_orders
      expect(stub).to have_been_made
    end

    it 'invokes callables fresh on every request' do
      tokens = %w[first second]
      client_class = build_client do
        base 'https://api.test'
        auth bearer: -> { tokens.shift }
        contract :ping, 'GET /ping'
      end

      stub1 = stub_request(:get, 'https://api.test/ping')
              .with(headers: { 'Authorization' => 'Bearer first' })
      stub2 = stub_request(:get, 'https://api.test/ping')
              .with(headers: { 'Authorization' => 'Bearer second' })

      client_class.new.ping
      client_class.new.ping
      expect(stub1).to have_been_made
      expect(stub2).to have_been_made
    end
  end

  describe 'api_key scheme' do
    it 'sends a custom header' do
      client_class = build_client do
        base 'https://api.test'
        auth api_key: { name: 'access-token', value: 'jwt-content' }
        contract :ping, 'GET /ping'
      end

      stub = stub_request(:get, 'https://api.test/ping')
             .with(headers: { 'access-token' => 'jwt-content' })

      client_class.new.ping
      expect(stub).to have_been_made
    end

    it 'supports multiple keys at once (dual-header auth)' do
      client_class = build_client do
        base 'https://api.test'
        auth api_key: [
          { name: 'access-token', value: -> { 'jwt' } },
          { name: 'client-id', value: 'cid-42' }
        ]
        contract :ping, 'GET /ping'
      end

      stub = stub_request(:get, 'https://api.test/ping')
             .with(headers: { 'access-token' => 'jwt', 'client-id' => 'cid-42' })

      client_class.new.ping
      expect(stub).to have_been_made
    end

    it 'can live in the query string' do
      client_class = build_client do
        base 'https://api.test'
        auth api_key: { name: 'api_key', value: 'secret', in: :query }
        contract :ping, 'GET /ping'
      end

      stub = stub_request(:get, 'https://api.test/ping')
             .with(query: { 'api_key' => 'secret' })

      client_class.new.ping
      expect(stub).to have_been_made
    end

    it 'merges query auth alongside declared query params' do
      client_class = build_client do
        base 'https://api.test'
        auth api_key: { name: 'token', value: 't1', in: :query }
        contract :list, 'GET /items' do
          param :page, Integer, default: 2
        end
      end

      stub = stub_request(:get, 'https://api.test/items')
             .with(query: { 'page' => '2', 'token' => 't1' })

      client_class.new.list
      expect(stub).to have_been_made
    end
  end

  describe 'basic scheme' do
    it 'encodes literal credentials' do
      client_class = build_client do
        base 'https://api.test'
        auth basic: %w[alice s3cret]
        contract :ping, 'GET /ping'
      end

      stub = stub_request(:get, 'https://api.test/ping')
             .with(headers: { 'Authorization' => "Basic #{['alice:s3cret'].pack('m0')}" })

      client_class.new.ping
      expect(stub).to have_been_made
    end

    it 'accepts a callable returning the pair' do
      client_class = build_client do
        base 'https://api.test'
        auth basic: -> { %w[u p] }
        contract :ping, 'GET /ping'
      end

      stub = stub_request(:get, 'https://api.test/ping')
             .with(headers: { 'Authorization' => "Basic #{['u:p'].pack('m0')}" })

      client_class.new.ping
      expect(stub).to have_been_made
    end
  end

  describe 'composition and precedence' do
    it 'combines multiple schemes in one declaration' do
      client_class = build_client do
        base 'https://api.test'
        auth bearer: 'tok', api_key: { name: 'x-key', value: 'kv' }
        contract :ping, 'GET /ping'
      end

      stub = stub_request(:get, 'https://api.test/ping')
             .with(headers: { 'Authorization' => 'Bearer tok', 'x-key' => 'kv' })

      client_class.new.ping
      expect(stub).to have_been_made
    end

    it 'overrides Authorization coming from default_headers' do
      client_class = build_client do
        base 'https://api.test'
        default_headers 'Authorization' => 'Bearer stale'
        auth bearer: 'fresh'
        contract :ping, 'GET /ping'
      end

      stub = stub_request(:get, 'https://api.test/ping')
             .with(headers: { 'Authorization' => 'Bearer fresh' })

      client_class.new.ping
      expect(stub).to have_been_made
    end

    it 'lets before_request callbacks override resolved credentials' do
      client_class = build_client do
        base 'https://api.test'
        auth bearer: 'contract-value'
        before_request { |ctx| ctx[:headers]['Authorization'] = 'Bearer callback-value' }
        contract :ping, 'GET /ping'
      end

      stub = stub_request(:get, 'https://api.test/ping')
             .with(headers: { 'Authorization' => 'Bearer callback-value' })

      client_class.new.ping
      expect(stub).to have_been_made
    end

    it 'is inherited down the class chain and overridable' do
      parent = build_client do
        base 'https://api.test'
        auth bearer: 'parent-token'
        contract :ping, 'GET /ping'
      end

      child = Class.new(parent) do
        auth bearer: 'child-token'
      end

      stub_parent = stub_request(:get, 'https://api.test/ping')
                    .with(headers: { 'Authorization' => 'Bearer parent-token' })
      parent.new.ping
      stub_child = stub_request(:get, 'https://api.test/ping')
                   .with(headers: { 'Authorization' => 'Bearer child-token' })
      child.new.ping

      expect(stub_parent).to have_been_made
      expect(stub_child).to have_been_made
    end
  end

  describe 'contract-level opt-out' do
    it 'omits auth for contracts that declare auth false' do
      stub = stub_request(:get, 'https://api.test/health')
             .with { |req| !req.headers.key?('Authorization') }

      client.health
      expect(stub).to have_been_made
    end

    it 'keeps auth on contracts that do not opt out' do
      stub = stub_request(:get, 'https://api.test/orders')
             .with(headers: { 'Authorization' => 'Bearer token-123' },
                   query: hash_including('page' => '1'))

      client.list_orders
      expect(stub).to have_been_made
    end
  end

  describe 'getter and validation' do
    it 'returns the resolved Auth object when called without arguments' do
      expect(client_class.auth).to be_a(Contractful::Contract::Auth)
      expect(client_class.auth.to_s).to eq 'bearer'
    end

    it 'rejects unknown schemes at definition time' do
      expect do
        build_client do
          base 'https://api.test'
          auth hmac: 'nope'
        end
      end.to raise_error(
        Contractful::Contract::InvalidDefinition,
        /unknown auth scheme :hmac/
      )
    end

    it 'rejects api_key entries without a name' do
      expect do
        build_client do
          base 'https://api.test'
          auth api_key: { value: 'v' }
        end
      end.to raise_error(Contractful::Contract::InvalidDefinition, /requires a name/)
    end

    it 'rejects invalid api_key locations' do
      expect do
        build_client do
          base 'https://api.test'
          auth api_key: { name: 'k', value: 'v', in: :body }
        end
      end.to raise_error(Contractful::Contract::InvalidDefinition, /must be :header or :query/)
    end

    it 'rejects non-literal, non-callable values' do
      expect do
        build_client do
          base 'https://api.test'
          auth bearer: 12_345
        end
      end.to raise_error(Contractful::Contract::InvalidDefinition, /literal or a callable/)
    end

    it 'returns nil from the getter form when no auth is configured' do
      fresh_class = build_client do
        base 'https://api.test'
        contract :ping, 'GET /ping'
      end
      expect(fresh_class.auth).to be_nil
    end

    it 'rejects scheme declarations inside a contract block' do
      expect do
        build_client do
          base 'https://api.test'
          contract :x, 'GET /x' do
            auth bearer: 'tok'
          end
        end
      end.to raise_error(
        Contractful::Contract::InvalidDefinition,
        /contract-level auth only accepts false/
      )
    end
  end
end
