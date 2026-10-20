# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe 'Contractful::Contract callbacks' do
  def build_client(&block)
    Class.new do
      include Contractful::Contract

      base 'https://api.test'
      instance_exec(&block)
    end
  end

  let(:client_class) do
    build_client do
      contract :list_posts, 'GET /posts' do
        param :page, Integer, default: 1
      end

      contract :create_post, 'POST /posts' do
        param :title, String, required: true
      end
    end
  end

  describe 'before_request' do
    it 'receives a mutable context and can inject headers' do
      klass = build_client do
        before_request do |ctx|
          ctx[:headers]['Authorization'] = 'Bearer token-123'
        end

        contract :list_posts, 'GET /posts'
      end

      stub = stub_request(:get, 'https://api.test/posts')
             .with(headers: { 'Authorization' => 'Bearer token-123' })

      klass.new.list_posts

      expect(stub).to have_been_requested
    end

    it 'can rewrite the outgoing URL' do
      klass = build_client do
        before_request { |ctx| ctx[:url] = ctx[:url].sub('api.test', 'mirror.test') }

        contract :list_posts, 'GET /posts'
      end

      stub_request(:get, 'https://api.test/posts') # must NOT be called
      stub = stub_request(:get, 'https://mirror.test/posts').to_return(body: '[]')

      klass.new.list_posts

      expect(stub).to have_been_requested
    end

    it 'exposes the definition, method and payload in the context' do
      seen = nil
      klass = build_client do
        before_request { |ctx| seen = ctx }

        contract(:create_post, 'POST /posts') { param :title, String, required: true }
      end
      stub_request(:post, 'https://api.test/posts')

      klass.new.create_post(title: 'Hi')

      expect(seen[:method]).to eq :post
      expect(seen[:url]).to eq 'https://api.test/posts'
      expect(seen[:payload]).to eq '{"title":"Hi"}'
      expect(seen[:definition]).to be_a(Contractful::Contract::Definition)
      expect(seen[:definition].name).to eq :create_post
    end

    it 'runs multiple callbacks in declaration order' do
      klass = build_client do
        before_request { |ctx| ctx[:headers]['X-First'] = '1' }
        before_request { |ctx| ctx[:headers]['X-Second'] = ctx[:headers]['X-First'] }
        contract :list_posts, 'GET /posts'
      end

      stub = stub_request(:get, 'https://api.test/posts')
             .with(headers: { 'X-First' => '1', 'X-Second' => '1' })

      klass.new.list_posts

      expect(stub).to have_been_requested
    end

    it 'propagates exceptions raised inside the callback' do
      klass = build_client do
        before_request { |_ctx| raise KeyError, 'no auth token' }
        contract :list_posts, 'GET /posts'
      end

      expect { klass.new.list_posts }.to raise_error(KeyError, /no auth token/)
    end
  end

  describe 'after_response' do
    it 'receives the response before the contract method returns' do
      seen = []
      klass = build_client do
        after_response { |response| seen << response }
        contract :list_posts, 'GET /posts'
      end
      stub_request(:get, 'https://api.test/posts').to_return(body: '[]')

      response = klass.new.list_posts

      expect(seen).to eq [response]
    end

    it 'runs after response validation' do
      seen = []
      klass = build_client do
        after_response { |response| seen << response }

        contract(:list_posts, 'GET /posts') { responds 200, type: :hash }
      end
      stub_request(:get, 'https://api.test/posts').to_return(body: '[1,2]')

      expect do
        klass.new.list_posts
      end.to raise_error(Contractful::Contract::UnexpectedResponse)
      expect(seen).to be_empty
    end

    it 'does not run when param validation fails' do
      seen = []
      klass = build_client do
        after_response { |response| seen << response }

        contract(:create_post, 'POST /posts') { param :title, String, required: true }
      end

      expect do
        klass.new.create_post
      end.to raise_error(Contractful::Contract::MissingParam)
      expect(seen).to be_empty
    end
  end

  describe 'inheritance' do
    let(:parent_class) do
      build_client do
        before_request { |ctx| ctx[:headers]['X-Parent'] = 'yes' }

        contract :list_posts, 'GET /posts'
      end
    end

    it 'subclasses inherit and extend the callback chain' do
      child_class = Class.new(parent_class) do
        before_request { |ctx| ctx[:headers]['X-Child'] = ctx[:headers]['X-Parent'] }
      end

      stub = stub_request(:get, 'https://api.test/posts')
             .with(headers: { 'X-Parent' => 'yes', 'X-Child' => 'yes' })

      child_class.new.list_posts

      expect(stub).to have_been_requested
    end

    it 'runs root-most callbacks first' do
      order = []
      base_class = build_client do
        before_request { |_ctx| order << :base }

        contract :list_posts, 'GET /posts'
      end
      child_class = Class.new(base_class) do
        before_request { |_ctx| order << :child }
      end
      stub_request(:get, 'https://api.test/posts')

      child_class.new.list_posts

      expect(order).to eq %i[base child]
    end

    it 'does not mutate the parent when the child adds callbacks' do
      Class.new(parent_class) do
        before_request { |ctx| ctx[:headers]['X-Child'] = 'yes' }
      end

      stub = stub_request(:get, 'https://api.test/posts')
             .with(headers: { 'X-Parent' => 'yes' })
             .with { |req| !req.headers.key?('X-Child') }

      parent_class.new.list_posts

      expect(stub).to have_been_requested
    end

    it 'chains after_response callbacks through the hierarchy' do
      seen = []
      child_class = Class.new(parent_class) do
        after_response { |response| seen << "child:#{response.code}" }
      end
      stub_request(:get, 'https://api.test/posts').to_return(body: '[]')

      child_class.new.list_posts

      expect(seen).to eq ['child:200']
    end
  end
end
