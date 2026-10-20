# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe 'Contractful::Contract idempotency keys' do
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
        idempotent true
      end

      contract :fire_and_forget, 'POST /events' do
        param :name, String, required: true
      end
    end
  end

  let(:client) { client_class.new }

  it 'injects a UUID key on idempotent contracts' do
    stub = stub_request(:post, 'https://api.test/orders')
           .with { |req| req.headers['Idempotency-Key'] =~ /\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/ }

    client.create_order(security_id: 'X1')
    expect(stub).to have_been_made
  end

  it 'does not inject a key on contracts that are not flagged' do
    stub = stub_request(:post, 'https://api.test/events')
           .with { |req| !req.headers.key?('Idempotency-Key') }

    client.fire_and_forget(name: 'tick')
    expect(stub).to have_been_made
  end

  it 'uses a per-call _idempotency_key verbatim' do
    stub = stub_request(:post, 'https://api.test/orders')
           .with(headers: { 'Idempotency-Key' => 'my-fixed-key' })

    client.create_order(security_id: 'X1', _idempotency_key: 'my-fixed-key')
    expect(stub).to have_been_made
  end

  it 'accepts a per-call key even on contracts that are not flagged' do
    stub = stub_request(:post, 'https://api.test/events')
           .with(headers: { 'Idempotency-Key' => 'caller-key' })

    client.fire_and_forget(name: 'tick', _idempotency_key: 'caller-key')
    expect(stub).to have_been_made
  end

  it 'generates a fresh key per logical call' do
    keys = []
    stub_request(:post, 'https://api.test/orders')
      .with do |req| 
      keys << req.headers['Idempotency-Key']
                     true
end

    client.create_order(security_id: 'X1')
    client.create_order(security_id: 'X2')
    expect(keys.length).to eq 2
    expect(keys.uniq.length).to eq 2
  end

  it 'keeps the key stable across automatic retries of the same call' do
    keys = []
    stub_request(:post, 'https://api.test/orders')
      .with do |req| 
      keys << req.headers['Idempotency-Key']
                     true
end
      .to_return(status: 503, headers: { 'Retry-After' => '0' })
      .then.to_return(status: 201, body: '{}')

    client.create_order(security_id: 'X1', _max_retries: 2)
    expect(keys.length).to eq 2
    expect(keys.uniq.length).to eq 1
  end

  it 'honors a custom header name' do
    client_class = build_client do
      base 'https://api.test'
      idempotency_header 'X-Request-ID'
      contract :pay, 'POST /payments' do
        idempotent true
      end
    end

    stub = stub_request(:post, 'https://api.test/payments')
           .with do |req|
             req.headers.any? { |k, _| k.casecmp('X-Request-Id').zero? } &&
               !req.headers.key?('Idempotency-Key')
           end

    client_class.new.pay
    expect(stub).to have_been_made
  end

  it 'honors a custom generator and inherits down the chain' do
    parent = build_client do
      base 'https://api.test'
      idempotency_generator -> { 'gen-1' }
      contract :pay, 'POST /payments' do
        idempotent true
      end
    end

    child = Class.new(parent) do
      idempotency_generator -> { 'gen-2' }
    end

    stub1 = stub_request(:post, 'https://api.test/payments')
            .with(headers: { 'Idempotency-Key' => 'gen-1' })
    parent.new.pay
    stub2 = stub_request(:post, 'https://api.test/payments')
            .with(headers: { 'Idempotency-Key' => 'gen-2' })
    child.new.pay

    expect(stub1).to have_been_made
    expect(stub2).to have_been_made
  end

  it 'coexists with contract auth' do
    client_class = build_client do
      base 'https://api.test'
      auth bearer: 'tok'
      contract :pay, 'POST /payments' do
        idempotent true
      end
    end

    stub = stub_request(:post, 'https://api.test/payments')
           .with(headers: {
                   'Authorization' => 'Bearer tok',
                   'Idempotency-Key' => /\h{8}-/
                 })

    client_class.new.pay
    expect(stub).to have_been_made
  end

  it 'rejects invalid header names and generators at definition time' do
    expect do
      build_client do
        base 'https://api.test'
        idempotency_header ''
      end
    end.to raise_error(Contractful::Contract::InvalidDefinition, /non-empty String/)

    expect do
      build_client do
        base 'https://api.test'
        idempotency_generator 'not-callable'
      end
    end.to raise_error(Contractful::Contract::InvalidDefinition, /respond to #call/)
  end

  it 'marks idempotent contracts in introspection' do
    definition = client_class.contract_for(:create_order)
    expect(definition.idempotent).to be true
    expect(definition.describe).to include('idempotent')
    expect(client_class.contract_for(:fire_and_forget).idempotent).to be_nil
  end
end
