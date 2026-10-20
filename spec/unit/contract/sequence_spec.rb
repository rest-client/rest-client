# frozen_string_literal: true

require_relative '../../spec_helper'
require 'contractful/contract/sequence'

RSpec.describe Contractful::Contract::Sequence do
  subject(:mod) { described_class }

  let(:client_class) do
    Class.new do
      include Contractful::Contract

      base 'https://seq.test'
      default_headers 'Accept' => 'application/json'

      contract :create_order, 'POST /orders' do
        param :quantity, Integer, min: 1, required: true
        param :order_type, String, inclusion: %w[LIMIT MARKET], default: 'MARKET'
        param :meta, Hash
        responds 201, 422, type: :hash
        response_field :order_id, :string, required: true
        response_field :status, :string
      end

      contract :set_flag, 'POST /flags' do
        param :enabled, :boolean, required: true
        responds 200, type: :hash
      end

      contract :get_order, 'GET /orders/:order_id' do
        param :order_id, String, required: true
        responds 200, 404, type: :hash
        response_field :order_id, :string, required: true
        response_field :status, :string
      end

      contract :list_orders, 'GET /orders' do
        responds 200, type: :array
      end

      contract :get_health, 'GET /health' do
        responds 200, type: :string
      end

      contract :flaky_probe, 'GET /flaky' do
        responds 200, 500, type: :hash
      end
    end
  end

  let(:client) { client_class.new }
  let(:fixture_path) do
    File.expand_path('../../fixtures/sequences/order_lifecycle.yml', __dir__)
  end

  def request_count
    WebMock::RequestRegistry.instance.requested_signatures.hash.values.sum
  end

  # A fresh fixture Hash on every call so tests can mutate their copy.
  def fixture
    {
      name: 'happy path',
      steps: [
        {
          call: 'create_order',
          params: { quantity: 10 },
          response: { status: 201, body: { order_id: 'o-1', status: 'open' } },
          expect_request: { json_include: { quantity: 10, order_type: 'MARKET' } }
        },
        {
          call: 'get_order',
          params: { order_id: 'o-1' },
          response: { status: 200, body: { order_id: 'o-1', status: 'filled' } },
          expect_request: { path: '/orders/o-1' }
        }
      ]
    }
  end

  after { WebMock.enable! }

  describe '.load — fixture validation' do
    it 'accepts a Hash and a YAML file path' do
      from_hash = mod.load(client, fixture)
      from_file = mod.load(client, fixture_path)

      expect(from_hash.steps.size).to eq 2
      expect(from_file.steps.size).to eq 2
      expect(from_file.name).to eq 'order lifecycle'
    end

    it 'rejects fixtures without a steps array' do
      expect { mod.load(client, { name: 'x' }) }
        .to raise_error(mod::InvalidFixture, /'steps' array/)
    end

    it 'rejects empty sequences' do
      expect { mod.load(client, { steps: [] }) }
        .to raise_error(mod::InvalidFixture, /declares no steps/)
    end

    it 'rejects steps naming unknown contracts' do
      bad = { steps: [{ call: 'nope', response: { status: 200 } }] }
      expect { mod.load(client, bad) }
        .to raise_error(mod::InvalidFixture, /:nope is not a contract on/)
    end

    it 'rejects steps without a recorded response' do
      bad = { steps: [{ call: 'list_orders' }] }
      expect { mod.load(client, bad) }
        .to raise_error(mod::InvalidFixture, /'response' Hash is required/)
    end

    it 'rejects non-integer or out-of-range statuses' do
      bad = { steps: [{ call: 'list_orders', response: { status: '200' } }] }
      expect { mod.load(client, bad) }
        .to raise_error(mod::InvalidFixture, /status must be an Integer/)
    end

    it 'rejects unknown expect_request keys (typo protection)' do
      bad = { steps: [{ call: 'list_orders', response: { status: 200 },
                        expect_request: { query_incldue: { page: 1 } } }] }
      expect { mod.load(client, bad) }
        .to raise_error(mod::InvalidFixture, /unknown expect_request keys :query_incldue/)
    end

    it 'rejects bodies that are neither raw strings nor JSON containers' do
      bad = { steps: [{ call: 'list_orders', response: { status: 200, body: 42 } }] }
      expect { mod.load(client, bad) }
        .to raise_error(mod::InvalidFixture, /response body must be a String/)
    end
  end

  describe '#run — happy path' do
    it 'drives the client through every recorded interaction' do
      results = mod.run(client, fixture)

      expect(results.size).to eq 2
      expect(results[0].step).to eq 1
      expect(results[0].response.code).to eq 201
      expect(results[0].response.json).to include('order_id' => 'o-1')
      expect(results[1].response.code).to eq 200
      expect(results[1].response.json).to include('status' => 'filled')
      expect(results[1].request.uri.path).to eq '/orders/o-1'
    end

    it 'handles raw-string and array response bodies' do
      steps = [
        { call: 'get_health', response: { status: 200, body: 'OK' } },
        { call: 'list_orders', response: { status: 200, body: [{ order_id: 'o-1' }] } }
      ]
      results = mod.run(client, { steps: steps })

      expect(results[0].response.body).to eq 'OK'
      expect(results[1].response.json).to eq([{ 'order_id' => 'o-1' }])
    end

    it 'serves JSON bodies with an application/json content type' do
      mod.run(client, fixture)
      first = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.first
      expect(first.headers['Content-Type']).to eq 'application/json'
      expect(first.uri.host).to eq 'seq.test'
    end
  end

  describe '#run — contract violations fail at their step' do
    it 'fails when a recorded response misses a required response_field' do
      bad = fixture
      bad[:steps][1][:response][:body] = { status: 'filled' } # order_id missing

      expect { mod.run(client, bad) }
        .to raise_error(mod::Failure, /step 2 \(get_order\): response violates contract/)
    end

    it 'fails when a recorded status is not declared by the contract' do
      bad = fixture
      bad[:steps][0][:response] = { status: 500, body: { error: 'boom' } }

      expect { mod.run(client, bad) }
        .to raise_error(mod::Failure, /step 1 \(create_order\): unexpected status 500/)
    end

    it 'fails on pre-network param violations with the step attached' do
      bad = fixture
      bad[:steps][0][:params] = { quantity: 0 }

      expect { mod.run(client, bad) }
        .to raise_error(mod::Failure, /step 1 \(create_order\): .*below minimum/)
    end

    it 'stops at the first violation — later steps never run' do
      executed = []
      bad = fixture
      bad[:steps][1][:response] = { status: 503, body: { error: 'down' } }
      bad[:steps] << { call: 'get_health', response: { status: 200, body: 'OK' } }

      player = mod.load(client, bad)
      player.after_step { |index| executed << index }

      expect { player.run }.to raise_error(mod::Failure)
      expect(executed).to eq [1]
      # step 2's HTTP request legitimately fired — the violation happens
      # when the recorded 503 comes back; step 3 never ran.
      expect(request_count).to eq 2
    end
  end

  describe '#run — outgoing request assertions' do
    it 'passes subset assertions for payload, headers and path' do
      steps = [
        { call: 'create_order', params: { quantity: 3 },
          response: { status: 201, body: { order_id: 'o-2' } },
          expect_request: {
            json_include: { quantity: 3, order_type: 'MARKET' },
            headers_include: { Accept: 'application/json' }
          } },
        { call: 'get_order', params: { order_id: 'o-2' },
          response: { status: 200, body: { order_id: 'o-2' } },
          expect_request: { path: '/orders/o-2' } }
      ]
      expect(mod.run(client, { steps: steps }).size).to eq 2
    end

    it 'supports nested payload subset assertions' do
      steps = [{ call: 'create_order',
                 params: { quantity: 5, meta: { source: 'bot' } },
                 response: { status: 201, body: { order_id: 'o-3' } },
                 expect_request: { json_include: { meta: { source: 'bot' } } } }]
      expect(mod.run(client, { steps: steps }).size).to eq 1
    end

    it 'treats false as a present value in JSON subset assertions' do
      steps = [{ call: 'set_flag',
                 params: { enabled: false },
                 response: { status: 200, body: {} },
                 expect_request: { json_include: { enabled: false } } }]
      expect(mod.run(client, { steps: steps }).size).to eq 1
    end

    it 'anchors stubbed paths so a prefix does not match a longer path' do
      steps = [
        { call: 'set_flag', params: { enabled: true },
          response: { status: 200, body: {} } },
        { call: 'get_health', response: { status: 200, body: 'ok' } }
      ]
      player = mod.load(client, { steps: steps })
      player.before_step do |number, _step|
        Contractful.post('https://seq.test/flags/extra', 'x') if number == 2
      end

      expect { player.run }.to raise_error(WebMock::NetConnectNotAllowedError)
    end

    it 'fails with the step number when the path is wrong' do
      steps = [{ call: 'get_order', params: { order_id: 'o-2' },
                 response: { status: 200, body: { order_id: 'o-2' } },
                 expect_request: { path: '/orders/OTHER' } }]
      expect { mod.run(client, { steps: steps }) }
        .to raise_error(mod::Failure, /step 1 \(get_order\): expected request path/)
    end

    it 'fails when a query param is missing or has the wrong value' do
      steps = [{ call: 'list_orders',
                 response: { status: 200, body: [] },
                 expect_request: { query_include: { page: '2' } } }]
      expect { mod.run(client, { steps: steps }) }
        .to raise_error(mod::Failure, /step 1 \(list_orders\): query params missing or wrong/)
    end

    it 'fails when a request header is missing' do
      steps = [{ call: 'list_orders',
                 response: { status: 200, body: [] },
                 expect_request: { headers_include: { 'X-Custom' => 'v' } } }]
      expect { mod.run(client, { steps: steps }) }
        .to raise_error(mod::Failure, /request headers missing or wrong/)
    end

    it 'fails when the JSON payload does not contain the expected subset' do
      steps = [{ call: 'create_order', params: { quantity: 5 },
                 response: { status: 201, body: { order_id: 'o-3' } },
                 expect_request: { json_include: { quantity: 6 } } }]
      expect { mod.run(client, { steps: steps }) }
        .to raise_error(mod::Failure, /expected quantity=6, got 5/)
    end

    it 'fails with a clear message when the payload is not JSON' do
      steps = [{ call: 'get_health',
                 response: { status: 200, body: 'OK' },
                 expect_request: { json_include: { x: 1 } } }]
      expect { mod.run(client, { steps: steps }) }
        .to raise_error(mod::Failure, /json_include assertion requires a JSON request payload/)
    end
  end

  describe 'stateful rules via hooks' do
    it 'lets after_step assert recorded vendor headers (rate-limit window)' do
      player = mod.load(client, fixture_path)

      results = nil
      player.after_step do |index, _step, response|
        next unless index == 2

        expect(response.rate_limit).not_to be_nil
        expect(response.rate_limit.remaining).to eq 4
        results = response
      end

      expect(player.run.size).to eq 2
      expect(results.code).to eq 200
    end

    it 'lets after_step enforce cross-step invariants (order id continuity)' do
      player = mod.load(client, fixture)
      first_order_id = nil

      player.after_step do |index, step, response|
        first_order_id = response.json['order_id'] if index == 1
        expect(step[:params][:order_id]).to eq first_order_id if index == 2
      end

      expect(player.run.size).to eq 2
    end

    it 'reports hook failures with the step number' do
      player = mod.load(client, fixture)
      player.before_step { |_i, step| raise 'token expired' if step[:call] == :get_order }

      expect { player.run }
        .to raise_error(mod::Failure, /step 2 \(get_order\): hook failed: token expired/)
    end
  end

  describe 'retry robustness' do
    it 'keeps step bookkeeping correct when the client retries internally' do
      # The contract declares the 500, so the recorded error response is
      # returned after the client's internal retry passes are exhausted.
      steps = [{ call: 'flaky_probe',
                 params: { _max_retries: 1, _retry_interval: 0 },
                 response: { status: 500, body: { error: 'down' } } }]

      results = mod.run(client, { steps: steps })

      expect(results.size).to eq 1
      expect(results.first.response.code).to eq 500
      expect(request_count).to eq 2
    end
  end

  describe 'webmock guards' do
    it 'raises a helpful error when WebMock is disabled' do
      WebMock.disable!
      expect { mod.run(client, fixture) }
        .to raise_error(mod::Error, /WebMock is loaded but not enabled/)
    end

    it 'can be required standalone without prior contractful requires' do
      cmd = [Gem.ruby, '-Ilib', '-rcontractful/contract/sequence', '-e', 'exit(0)']
      expect(system(*cmd)).to be(true)
    end
  end
end
