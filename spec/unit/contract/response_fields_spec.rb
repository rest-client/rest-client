# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe 'Contractful::Contract response fields (open response schemas)' do
  # Contract-first semantics being tested here, per the design philosophy:
  #
  #   * Request schemas are CLOSED — declared required fields and types bind.
  #   * Response schemas are OPEN — required fields and their types bind,
  #     but new fields and new enum members are additive, so unknown values
  #     are data, not errors.

  def build_client(&block)
    Class.new do
      include Contractful::Contract

      instance_exec(&block)
    end
  end

  let(:client_class) do
    build_client do
      base 'https://api.test'

      contract :create_order, 'POST /orders' do
        param :security_id, String, required: true
        param :quantity, Integer, required: true, min: 1

        response_field :order_id, :string, required: true
        response_field :status, :string
      end
    end
  end

  let(:client) { client_class.new }

  def stub_order_response(status, body)
    stub_request(:post, 'https://api.test/orders')
      .to_return(status: status, body: JSON.generate(body),
                 headers: { 'Content-Type' => 'application/json' })
  end

  describe 'definition-time validation' do
    it 'rejects unsupported field types' do
      expect do
        build_client do
          base 'https://api.test'
          contract :x, 'GET /x' do
            response_field :a, :nonsense
          end
        end
      end.to raise_error(
        Contractful::Contract::InvalidDefinition,
        /unsupported response_field type :nonsense/
      )
    end

    it 'rejects non-class, non-symbol types' do
      expect do
        build_client do
          base 'https://api.test'
          contract :x, 'GET /x' do
            response_field :a, 'String'
          end
        end
      end.to raise_error(
        Contractful::Contract::InvalidDefinition,
        /expected a Class or a supported symbol/
      )
    end

    it 'rejects inclusion that does not respond to include?' do
      expect do
        build_client do
          base 'https://api.test'
          contract :x, 'GET /x' do
            response_field :a, inclusion: 1
          end
        end
      end.to raise_error(
        Contractful::Contract::InvalidDefinition,
        /inclusion must respond to #include\?/
      )
    end

    it 'rejects response fields on a String-typed response' do
      expect do
        build_client do
          base 'https://api.test'
          contract :x, 'GET /x' do
            responds 200, type: String
            response_field :a
          end
        end
      end.to raise_error(
        Contractful::Contract::InvalidDefinition,
        /response_field cannot be used with a String response type/
      )
    end

    it 'exposes declared fields for introspection' do
      definition = client_class.contract_for(:create_order)
      expect(definition.response_fields.keys).to eq %i[order_id status]
      expect(definition.describe)
        .to include('(fields: :order_id, :status)')
    end
  end

  describe 'required fields bind' do
    it 'accepts a response that satisfies the contract' do
      stub_order_response(201, order_id: 'ORD-1', status: 'PENDING')
      response = client.create_order(security_id: '1', quantity: 1)
      expect(response.code).to eq 201
    end

    it 'raises when a required field is missing' do
      stub_order_response(201, status: 'PENDING')
      expect do
        client.create_order(security_id: '1', quantity: 1)
      end.to raise_error(
        Contractful::Contract::UnexpectedResponse,
        /field :order_id is required but missing/
      )
    end

    it 'raises when a required field is null' do
      stub_order_response(201, order_id: nil, status: 'PENDING')
      expect do
        client.create_order(security_id: '1', quantity: 1)
      end.to raise_error(
        Contractful::Contract::UnexpectedResponse,
        /field :order_id is required but was null/
      )
    end
  end

  describe 'types bind, but nothing else does' do
    it 'raises when a declared field comes back with the wrong type' do
      # The user's example: a response where orderId comes back as an
      # integer is a contract violation and raises on return.
      stub_order_response(201, order_id: 12_345, status: 'PENDING')
      expect do
        client.create_order(security_id: '1', quantity: 1)
      end.to raise_error(
        Contractful::Contract::UnexpectedResponse,
        /field :order_id expected String, got Integer/
      )
    end

    it 'treats undeclared response fields as data, never errors' do
      stub_order_response(
        201,
        order_id: 'ORD-1', status: 'PENDING',
        avg_price: 150.25, new_vendor_field: { nested: true }
      )
      expect do
        client.create_order(security_id: '1', quantity: 1)
      end.not_to raise_error
    end

    it 'treats nil values of optional fields as additive data' do
      stub_order_response(201, order_id: 'ORD-1', status: nil)
      expect do
        client.create_order(security_id: '1', quantity: 1)
      end.not_to raise_error
    end

    it 'validates booleans and numbers through symbol aliases' do
      client_class = build_client do
        base 'https://api.test'
        contract :x, 'GET /x' do
          response_field :flag, :boolean
          response_field :price, :number
        end
      end

      stub_request(:get, 'https://api.test/x')
        .to_return(body: JSON.generate(flag: 'yes', price: 1))
      expect { client_class.new.x }
        .to raise_error(/field :flag expected boolean, got String/)
    end

    it 'does not coerce values: what the server sent is what you inspect' do
      stub_order_response(201, order_id: 'ORD-1', status: 'PENDING')
      response = client.create_order(security_id: '1', quantity: 1)
      parsed = JSON.parse(response.body)
      expect(parsed['order_id']).to eq 'ORD-1'
      expect(parsed).to have_key('status')
    end
  end

  describe 'enum members are additive on responses' do
    let(:client_class) do
      build_client do
        base 'https://api.test'

        contract :create_order, 'POST /orders' do
          param :security_id, String, required: true
          param :quantity, Integer, required: true, min: 1

          response_field :order_id, :string, required: true
          # Open by default: new order states must not break old clients.
          response_field :status, :string, inclusion: %w[PENDING TRADED]
        end
      end
    end

    it 'accepts unknown enum members by default (data, not errors)' do
      stub_order_response(201, order_id: 'ORD-1', status: 'SETTLED_PARTIAL')
      expect do
        client.create_order(security_id: '1', quantity: 1)
      end.not_to raise_error
    end

    it 'enforces the inclusion set only for fields declared strict: true' do
      client_class = build_client do
        base 'https://api.test'
        contract :x, 'GET /x' do
          response_field :side, :string, inclusion: %w[BUY SELL], strict: true
        end
      end

      stub_request(:get, 'https://api.test/x')
        .to_return(body: JSON.generate(side: 'SHORT'))
      expect { client_class.new.x }
        .to raise_error(/field :side value "SHORT" is not in \["BUY", "SELL"\]/)
    end
  end

  describe 'body shape requirements' do
    it 'requires a JSON object body when fields are declared' do
      stub_request(:post, 'https://api.test/orders')
        .to_return(body: JSON.generate(%w[an array]))
      expect do
        client.create_order(security_id: '1', quantity: 1)
      end.to raise_error(
        Contractful::Contract::UnexpectedResponse,
        /expected a JSON object but got Array/
      )
    end

    it 'requires a parseable body' do
      stub_request(:post, 'https://api.test/orders').to_return(body: 'ok')
      expect do
        client.create_order(security_id: '1', quantity: 1)
      end.to raise_error(
        Contractful::Contract::UnexpectedResponse,
        /response body is not valid JSON/
      )
    end

    it 'rejects an empty body' do
      stub_request(:post, 'https://api.test/orders').to_return(body: '')
      expect do
        client.create_order(security_id: '1', quantity: 1)
      end.to raise_error(
        Contractful::Contract::UnexpectedResponse,
        /response body is empty/
      )
    end
  end

  describe 'aggregate violations' do
    it 'reports every violation in one error' do
      stub_order_response(201, status: 42)
      expect do
        client.create_order(security_id: '1', quantity: 1)
      end.to raise_error(
        Contractful::Contract::UnexpectedResponse
      ) { |e|
        expect(e.message).to match(/field :order_id is required but missing/)
        expect(e.message).to match(/field :status expected String, got Integer/)
      }
    end
  end

  describe 'ResponseField unit behavior' do
    let(:field) { Contractful::Contract::ResponseField.new(:status, :string, required: true) }

    it 'collects missing and null violations' do
      expect(field.violations_for({})).to eq ['field :status is required but missing']
      expect(field.violations_for({ status: nil }))
        .to eq ['field :status is required but was null']
    end

    it 'passes conforming payloads' do
      expect(field.violations_for({ status: 'TRADED', extra: 1 })).to eq []
    end

    it 'summarizes itself for introspection' do
      expect(field.to_s).to eq 'String, required'
      expect(Contractful::Contract::ResponseField.new(:a, :number).to_s).to eq 'number'
    end
  end
end
