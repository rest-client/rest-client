# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe 'Contractful::Contract resource macro' do
  def build_client(&block)
    Class.new do
      include Contractful::Contract

      base 'https://api.test'
      instance_exec(&block)
    end
  end

  let(:client_class) do
    build_client { resource :posts }
  end
  let(:client) { client_class.new }

  describe 'generated contracts' do
    it 'generates the five standard REST contracts' do
      expect(client_class.__own_contract_config.contracts.keys)
        .to contain_exactly(:list_posts, :get_post, :create_post, :update_post, :delete_post)

      expect(client_class.__own_contract_config.contracts[:list_posts].describe)
        .to eq 'GET /posts'
      expect(client_class.__own_contract_config.contracts[:get_post].describe)
        .to eq 'GET /posts/:id (params: :id)'
      expect(client_class.__own_contract_config.contracts[:create_post].describe)
        .to eq 'POST /posts'
      expect(client_class.__own_contract_config.contracts[:update_post].describe)
        .to eq 'PATCH /posts/:id (params: :id)'
      expect(client_class.__own_contract_config.contracts[:delete_post].describe)
        .to eq 'DELETE /posts/:id (params: :id)'
    end

    it 'returns the action => contract-name map' do
      mapping = client_class.resource :comments
      expect(mapping).to eq(
        index: :list_comments,
        show: :get_comment,
        create: :create_comment,
        update: :update_comment,
        destroy: :delete_comment
      )
    end

    it 'executes the generated contracts end-to-end' do
      stub_request(:get, 'https://api.test/posts?page=2').to_return(body: '[]')
      stub_request(:get, 'https://api.test/posts/7').to_return(body: '{"id":7}')
      stub_request(:post, 'https://api.test/posts')
        .with(body: '{"title":"Hi"}').to_return(status: 201, body: '{"id":8}')
      stub_request(:patch, 'https://api.test/posts/7')
        .with(body: '{"title":"New"}').to_return(body: '{"id":7}')
      stub_request(:delete, 'https://api.test/posts/7').to_return(status: 204)

      expect(client.list_posts(page: 2).body).to eq '[]'
      expect(client.get_post(id: 7).body).to eq '{"id":7}'
      expect(client.create_post(title: 'Hi').code).to eq 201
      expect(client.update_post(id: 7, title: 'New').body).to eq '{"id":7}'
      expect(client.delete_post(id: 7).code).to eq 204
    end

    it 'generates *_url builders for the CRUD contracts' do
      expect(client.get_post_url(id: 42)).to eq 'https://api.test/posts/42'
    end

    it 'raises MissingParam when :id is absent' do
      expect { client.get_post }.to raise_error(
        Contractful::Contract::MissingParam, /param :id is required/
      )
    end

    it 'sends remaining params per the verb defaults' do
      stub = stub_request(:get, 'https://api.test/posts')
             .with(query: hash_including('author' => 'octo'))
      stub_request(:patch, 'https://api.test/posts/7')
        .with(body: '{"title":"New","views":3}')

      client.list_posts(author: 'octo')
      client.update_post(id: 7, title: 'New', views: 3)

      expect(stub).to have_been_requested
    end
  end

  describe 'options' do
    it 'restricts actions with only:' do
      client_class = build_client { resource :posts, only: %i[index show] }

      expect(client_class.__own_contract_config.contracts.keys)
        .to contain_exactly(:list_posts, :get_post)
    end

    it 'accepts a single symbol for only:' do
      client_class = build_client { resource :posts, only: :index }

      expect(client_class.__own_contract_config.contracts.keys)
        .to contain_exactly(:list_posts)
    end

    it 'excludes actions with except:' do
      client_class = build_client { resource :posts, except: :destroy }

      expect(client_class.__own_contract_config.contracts.keys)
        .to contain_exactly(:list_posts, :get_post, :create_post, :update_post)
    end

    it 'rejects using only: and except: together' do
      expect do
        build_client { resource :posts, only: [:index], except: [:show] }
      end.to raise_error(Contractful::Contract::InvalidDefinition, /accepts :only or :except, not both/)
    end

    it 'rejects unknown action names' do
      expect do
        build_client { resource :posts, only: %i[index upsert] }
      end.to raise_error(Contractful::Contract::InvalidDefinition, /unknown resource actions :upsert/)
    end

    it 'supports update_with: :put' do
      client_class = build_client { resource :posts, update_with: :put }

      expect(client_class.__own_contract_config.contracts[:update_post].describe)
        .to eq 'PUT /posts/:id (params: :id)'
    end

    it 'rejects other update verbs' do
      expect do
        build_client { resource :posts, update_with: :post }
      end.to raise_error(Contractful::Contract::InvalidDefinition, /update_with must be :patch or :put/)
    end

    it 'supports a custom collection path' do
      client_class = build_client { resource :posts, path: '/v2/articles' }

      expect(client_class.__own_contract_config.contracts[:list_posts].describe)
        .to eq 'GET /v2/articles'
      expect(client_class.__own_contract_config.contracts[:get_post].describe)
        .to eq 'GET /v2/articles/:id (params: :id)'
    end

    it 'rejects paths that do not start with a slash' do
      expect do
        build_client { resource :posts, path: 'v2/posts' }
      end.to raise_error(Contractful::Contract::InvalidDefinition, %r{must start with "/"})
    end

    it 'supports an explicit singular name' do
      client_class = build_client { resource :people, singular: :human }

      expect(client_class.__own_contract_config.contracts[:get_human].describe)
        .to eq 'GET /people/:id (params: :id)'
      expect(client_class.__own_contract_config.contracts[:list_people].describe)
        .to eq 'GET /people'
    end
  end

  describe 'singularization' do
    {
      posts: 'post',
      categories: 'category',
      statuses: 'status',
      boxes: 'box',
      watches: 'watch',
      people: 'person',
      children: 'child'
    }.each do |plural, singular|
      it "singularizes :#{plural} to :#{singular}" do
        client_class = build_client { resource plural }
        expect(client_class.__own_contract_config.contracts)
          .to include(:"get_#{singular}")
      end
    end

    it 'rejects invalid resource names' do
      expect do
        build_client { resource 'not a name' }
      end.to raise_error(Contractful::Contract::InvalidDefinition, /not a valid identifier/)
    end
  end
end
