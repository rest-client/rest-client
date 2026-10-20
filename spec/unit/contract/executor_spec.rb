# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe 'Contractful::Contract executor' do
  def build_client(&block)
    Class.new do
      include Contractful::Contract

      instance_exec(&block)
    end
  end

  describe 'generated contract methods' do
    let(:client_class) do
      build_client do
        base 'https://api.test'
        default_headers 'Accept' => 'application/json'

        contract :list_posts, 'GET /posts' do
          param :page, Integer, default: 1
          param :per_page, Integer, default: 25, inclusion: (1..100)
          param :q, String
        end

        contract :create_post, 'POST /posts' do
          param :title, String, required: true
          param :tags, Array, default: []
          param :published, :boolean, default: false
        end
      end
    end

    let(:client) { client_class.new }

    it 'sends declared params as a query string for GET contracts' do
      stub = stub_request(:get, 'https://api.test/posts')
             .with(query: { 'page' => '2', 'per_page' => '25' })

      client.list_posts(page: 2)

      expect(stub).to have_been_requested
    end

    it 'applies declared defaults' do
      stub = stub_request(:get, 'https://api.test/posts')
             .with(query: hash_including('page' => '1', 'per_page' => '25'))

      client.list_posts

      expect(stub).to have_been_requested
    end

    it 'coerces and validates params before the request' do
      expect do
        client.list_posts(per_page: 500)
      end.to raise_error(
        Contractful::Contract::InvalidParam,
        /param :per_page: value 500 is not in 1\.\.100/
      )
    end

    it 'rejects unknown params in strict mode' do
      expect do
        client.list_posts(bogus: 1)
      end.to raise_error(
        Contractful::Contract::UnknownParam,
        %r{unknown param :bogus for GET /posts}
      )
    end

    it 'rejects missing required params' do
      expect do
        client.create_post
      end.to raise_error(
        Contractful::Contract::MissingParam,
        %r{param :title is required by POST /posts}
      )
    end

    it 'sends remaining params as a JSON payload for POST contracts' do
      stub = stub_request(:post, 'https://api.test/posts')
             .with(
               body: '{"title":"Hello","tags":[],"published":false}',
               headers: { 'Content-Type' => 'application/json' }
             )

      client.create_post(title: 'Hello')

      expect(stub).to have_been_requested
    end

    it 'coerces param values in the payload' do
      stub = stub_request(:post, 'https://api.test/posts')
             .with(body: /"published":true/)

      client.create_post(title: 'Hi', published: 'yes')

      expect(stub).to have_been_requested
    end

    it 'merges class default headers, instance overrides and call _headers' do
      stub = stub_request(:get, 'https://api.test/posts')
             .with(
               query: hash_including('page' => '1', 'per_page' => '25'),
               headers: {
                 'Accept' => 'application/json',
                 'X-Instance' => 'yes',
                 'X-Call' => 'yes'
               }
             )

      typed = client_class.new(headers: { 'X-Instance' => 'yes' })
      typed.list_posts(_headers: { 'X-Call' => 'yes' })

      expect(stub).to have_been_requested
    end

    it 'returns the Contractful::Response' do
      stub_request(:get, 'https://api.test/posts')
        .with(query: hash_including('page' => '1', 'per_page' => '25'))
        .to_return(body: '[]')

      response = client.list_posts

      expect(response).to be_a(Contractful::Response)
      expect(response.body).to eq '[]'
    end

    it 'accepts string param keys' do
      stub = stub_request(:get, 'https://api.test/posts')
             .with(query: hash_including('q' => 'ruby'))

      client.list_posts('q' => 'ruby')

      expect(stub).to have_been_requested
    end

    it 'forwards meta options to the underlying request' do
      response_double = double('response', code: 200, body: '{}')
      expect(Contractful::Request).to receive(:execute).with(
        hash_including(timeout: 5, persistent: true, max_retries: 2)
      ).and_return(response_double)

      client.list_posts(_timeout: 5, _persistent: true, _max_retries: 2)
    end

    it 'rejects unknown meta options' do
      expect do
        client.list_posts(_timeots: 5)
      end.to raise_error(Contractful::Contract::UnknownParam, /unknown meta option :_timeots/)
    end

    it 'raises MissingBaseUrl when no base is configured' do
      baseless = build_client do
        contract :list_posts, 'GET /posts'
      end

      expect { baseless.new.list_posts }.to raise_error(
        Contractful::Contract::MissingBaseUrl, /no base URL configured/
      )
    end

    it 'sends a JSON payload with a Content-Type when params remain' do
      stub = stub_request(:post, 'https://api.test/posts')
             .with(body: '{"title":"Hi","tags":[],"published":false}')

      client.create_post(title: 'Hi')

      expect(stub).to have_been_requested
    end
  end

  describe 'path params' do
    let(:client_class) do
      build_client do
        base 'https://api.test'

        contract :create_issue, 'POST /repos/:owner/:repo/issues' do
          param :title, String, required: true
        end

        contract :show_issue, 'GET /repos/:owner/:repo/issues/:number' do
          param :number, Integer
        end
      end
    end

    let(:client) { client_class.new }

    it 'interpolates path placeholders into the URL' do
      stub = stub_request(:post, 'https://api.test/repos/octo/hello/issues')
             .with(body: '{"title":"Hi"}')

      client.create_issue(owner: 'octo', repo: 'hello', title: 'Hi')

      expect(stub).to have_been_requested
    end

    it 'does not repeat path params in the payload or query' do
      # Pin both halves of the intent in the stub match: the payload contains
      # only the fields that are not path placeholders, and no query string
      # is appended with the interpolated path params.
      stub = stub_request(:post, 'https://api.test/repos/octo/hello/issues')
             .with(body: '{"title":"Hi"}', query: {})

      client.create_issue(owner: 'octo', repo: 'hello', title: 'Hi')

      expect(stub).to have_been_requested
    end

    it 'coerces declared path params' do
      stub = stub_request(:get, 'https://api.test/repos/octo/hello/issues/42')

      client.show_issue(owner: 'octo', repo: 'hello', number: '42')

      expect(stub).to have_been_requested
    end

    it 'raises MissingParam when a path param is absent' do
      expect do
        client.create_issue(owner: 'octo', title: 'Hi')
      end.to raise_error(
        Contractful::Contract::MissingParam,
        %r{param :repo is required by POST /repos/:owner/:repo/issues}
      )
    end
  end

  describe 'payload styles' do
    it 'sends form-encoded payloads when the contract opts in' do
      client_class = build_client do
        base 'https://api.test'

        contract :login, 'POST /session' do
          payload_style :form
          param :user, String, required: true
          param :password, String, required: true
        end
      end

      stub = stub_request(:post, 'https://api.test/session')
             .with(body: { 'user' => 'alice', 'password' => 's3cret' })

      client_class.new.login(user: 'alice', password: 's3cret')

      expect(stub).to have_been_requested
    end

    it 'honors a class-level payload_style' do
      client_class = build_client do
        base 'https://api.test'
        payload_style :form

        contract :create_post, 'POST /posts' do
          param :title, String, required: true
        end
      end

      stub = stub_request(:post, 'https://api.test/posts')
             .with(body: { 'title' => 'Hi' })

      client_class.new.create_post(title: 'Hi')

      expect(stub).to have_been_requested
    end

    it 'lets query-style verbs send params in the query string' do
      client_class = build_client do
        base 'https://api.test'

        contract :destroy_post, 'DELETE /posts/:id' do
          param :reason, String
        end
      end

      stub = stub_request(:delete, 'https://api.test/posts/7')
             .with(query: { 'reason' => 'spam' })

      client_class.new.destroy_post(id: 7, reason: 'spam')

      expect(stub).to have_been_requested
    end
  end

  describe 'non-strict mode' do
    it 'lets undeclared params flow through to the request' do
      client_class = build_client do
        base 'https://api.test'
        strict_params false

        contract :list_posts, 'GET /posts' do
          param :page, Integer, default: 1
        end
      end

      stub = stub_request(:get, 'https://api.test/posts')
             .with(query: hash_including('page' => '1', 'extra' => 'goes-through'))

      client_class.new.list_posts(extra: 'goes-through')

      expect(stub).to have_been_requested
    end
  end

  describe 'generated *_url builders' do
    let(:client_class) do
      build_client do
        base 'https://api.test'

        contract :show_issue, 'GET /repos/:owner/:repo/issues/:number' do
          param :number, Integer
        end
      end
    end

    it 'expands path params and returns the full URL' do
      url = client_class.new.show_issue_url(owner: 'octo', repo: 'hi', number: '42')
      expect(url).to eq 'https://api.test/repos/octo/hi/issues/42'
    end

    it 'validates and coerces declared path params' do
      expect do
        client_class.new.show_issue_url(owner: 'octo', repo: 'hi', number: 'x')
      end.to raise_error(Contractful::Contract::InvalidParam, /param :number/)
    end

    it 'raises MissingParam for absent path params' do
      expect do
        client_class.new.show_issue_url(owner: 'octo')
      end.to raise_error(Contractful::Contract::MissingParam, /path param :repo is required/)
    end
  end

  describe 'instance-level base override' do
    it 'takes precedence over the class base' do
      client_class = build_client do
        base 'https://api.test'

        contract :list_posts, 'GET /posts'
      end

      stub = stub_request(:get, 'https://staging.test/posts')

      client_class.new(base: 'https://staging.test').list_posts

      expect(stub).to have_been_requested
    end

    it 'does not crash when a subclass defines initialize without calling super' do
      client_class = build_client do
        base 'https://api.test'

        contract :list_posts, 'GET /posts'
      end

      # A subclass that owns its constructor (e.g. taking other arguments)
      # and forgets `super` must not blow up inside header merging.
      subclass = Class.new(client_class) do
        def initialize(_token) # rubocop:disable Lint/MissingSuper
          # deliberately no super(base:, headers:) — the missing super call
          # is the exact behavior under test here.
        end
      end

      stub = stub_request(:get, 'https://api.test/posts')

      subclass.new('token').list_posts

      expect(stub).to have_been_requested
    end
  end

  describe 'definition-time validation' do
    it 'rejects invalid request lines' do
      expect do
        build_client { contract :x, 'FETCH /posts' }
      end.to raise_error(
        Contractful::Contract::InvalidDefinition,
        %r{invalid request line "FETCH /posts"}
      )
    end

    it 'rejects invalid base URLs' do
      expect do
        build_client { base 'ftp://nope' }
      end.to raise_error(Contractful::Contract::InvalidDefinition, /base must be an absolute http\(s\) URL/)
    end

    it 'rejects reserved contract names' do
      expect do
        build_client { contract :inspect, 'GET /x' }
      end.to raise_error(Contractful::Contract::InvalidDefinition, /is reserved/)
    end

    it 'rejects invalid contract names' do
      expect do
        build_client { contract 'not a name', 'GET /x' }
      end.to raise_error(Contractful::Contract::InvalidDefinition, /not a valid method name/)
    end
  end

  describe 'closed request schemas' do
    # Mirrors the contract-first principle: `quantity: {type: integer, minimum: 1}`
    # style constraints are enforced BEFORE the transport is touched — a
    # violating call must raise without any HTTP request being made.
    let(:client_class) do
      build_client do
        base 'https://api.test'

        contract :create_order, 'POST /orders' do
          param :security_id, String, required: true
          param :transaction_type, String, required: true, inclusion: %w[BUY SELL]
          param :quantity, Integer, required: true, min: 1
        end
      end
    end

    let(:client) { client_class.new }

    it 'accepts input inside the closed schema' do
      stub = stub_request(:post, 'https://api.test/orders')
             .with(body: { security_id: '12345', transaction_type: 'BUY', quantity: 10 })

      client.create_order(security_id: '12345', transaction_type: 'BUY', quantity: 10)
      expect(stub).to have_been_made
    end

    it 'rejects out-of-range input before the network is touched' do
      expect do
        client.create_order(security_id: '12345', transaction_type: 'BUY', quantity: 0)
      end.to raise_error(Contractful::Contract::InvalidParam, /below minimum 1/)

      expect(a_request(:post, 'https://api.test/orders')).not_to have_been_made
    end

    it 'rejects enum violations before the network is touched' do
      expect do
        client.create_order(security_id: '12345', transaction_type: 'HOLD', quantity: 1)
      end.to raise_error(Contractful::Contract::InvalidParam, /not in \["BUY", "SELL"\]/)

      expect(a_request(:post, 'https://api.test/orders')).not_to have_been_made
    end

    it 'retries retryable server errors (503) declared via responds' do
      client_class = build_client do
        base 'https://api.test'

        contract :create_order, 'POST /orders' do
          param :security_id, String, required: true
          responds 200, 201, 503
        end
      end

      stub_request(:post, 'https://api.test/orders')
        .to_return(status: 503, headers: { 'Retry-After' => '0' })
        .then.to_return(status: 201, body: JSON.generate(order_id: 'ORD-9'))

      response = client_class.new.create_order(security_id: 'X1', _max_retries: 2)
      expect(response.code).to eq 201
      expect(a_request(:post, 'https://api.test/orders')).to have_been_made.twice
    end
  end
end
