# frozen_string_literal: true

require_relative '_lib'

# Live integration tests for the contract-first DSL against httpbin.org.
RSpec.describe 'Contractful::Contract integration', :live do
  before(:all) do
    WebMock.disable!
  end

  after(:all) do
    WebMock.enable!
  end

  let(:client_class) do
    Class.new do
      include Contractful::Contract

      base 'https://httpbin.org'

      before_request do |ctx|
        ctx[:headers]['X-Contract-Test'] = 'yes'
      end

      contract :anything_get, 'GET /anything/:kind' do
        param :kind, String, required: true
        param :page, Integer, default: 1
        responds 200, type: :hash
      end

      contract :anything_post, 'POST /anything/:kind' do
        param :kind, String, required: true
        param :name, String, required: true
        param :tags, Array, default: []
        responds 200, type: :hash
      end
    end
  end

  it 'executes a GET contract with path params, defaults and callbacks' do
    response = client_class.new.anything_get(kind: 'read', page: 2)

    expect(response.code).to eq 200
    body = response.json
    expect(body['url']).to eq 'https://httpbin.org/anything/read?page=2'
    expect(body['headers']['X-Contract-Test']).to eq 'yes'
  end

  it 'executes a POST contract with a JSON payload' do
    response = client_class.new.anything_post(kind: 'write', name: 'post-1', tags: %w[a b])

    expect(response.code).to eq 200
    body = response.json
    expect(body['headers']['Content-Type']).to start_with('application/json')
    expect(body['json']).to eq('name' => 'post-1', 'tags' => %w[a b])
  end

  it 'validates response contracts against the live server' do
    expect do
      client_class.new.anything_get(kind: 'read')
    end.not_to raise_error
  end

  it 'raises MissingParam before any HTTP traffic when a param is absent' do
    expect do
      client_class.new.anything_post(name: 'no-kind-here')
    end.to raise_error(Contractful::Contract::MissingParam, /param :kind is required/)
  end
end
