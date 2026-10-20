# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe 'Contractful::Contract reflection and dynamic dispatch' do
  def build_client(&block)
    Class.new do
      include Contractful::Contract

      base 'https://api.test'
      instance_exec(&block)
    end
  end

  let(:client_class) do
    build_client do
      contract(:list_posts, 'GET /posts') { param :page, Integer, default: 1 }
      contract(:create_post, 'POST /posts') { param :title, String, required: true }
    end
  end
  let(:client) { client_class.new }

  describe 'class-level introspection' do
    it 'exposes the contract registry' do
      expect(client_class.contracts.keys).to contain_exactly(:list_posts, :create_post)
      expect(client_class.contracts[:list_posts]).to be_a(Contractful::Contract::Definition)
    end

    it 'returns a defensive copy from .contracts' do
      client_class.contracts.delete(:list_posts)
      expect(client_class.contract?(:list_posts)).to be true
    end

    it 'lists contract names' do
      expect(client_class.contract_names).to contain_exactly(:list_posts, :create_post)
    end

    it 'answers contract? for symbols and strings' do
      expect(client_class.contract?(:list_posts)).to be true
      expect(client_class.contract?('create_post')).to be true
      expect(client_class.contract?(:nope)).to be false
    end

    it 'looks up definitions with contract_for' do
      definition = client_class.contract_for('list_posts')
      expect(definition.verb).to eq :get
      expect(client_class.contract_for(:nope)).to be_nil
    end
  end

  describe 'inheritance-aware introspection' do
    let(:parent_class) do
      build_client do
        contract(:list_posts, 'GET /posts')
        contract(:audit_log, 'GET /audit')
      end
    end

    let(:child_class) do
      Class.new(parent_class) do
        contract(:list_posts, 'GET /v2/posts') # override
        contract(:create_post, 'POST /posts')  # extension
      end
    end

    it 'sees ancestor contracts from the subclass' do
      expect(child_class.contract_names)
        .to contain_exactly(:list_posts, :audit_log, :create_post)
    end

    it 'lets the subclass override win' do
      expect(child_class.contract_for(:list_posts).path_template).to eq '/v2/posts'
      expect(parent_class.contract_for(:list_posts).path_template).to eq '/posts'
    end

    it 'does not leak subclass contracts into the parent' do
      expect(parent_class.contract?(:create_post)).to be false
    end
  end

  describe 'instance-level introspection' do
    it 'delegates to the class' do
      expect(client.contracts.keys).to contain_exactly(:list_posts, :create_post)
      expect(client.contract_names).to contain_exactly(:list_posts, :create_post)
      expect(client.contract?(:list_posts)).to be true
      expect(client.contract_for(:list_posts)).to be_a(Contractful::Contract::Definition)
    end
  end

  describe 'dynamic dispatch' do
    it 'executes contracts via call_*' do
      stub = stub_request(:get, 'https://api.test/posts')
             .with(query: hash_including('page' => '3'))

      client.call_list_posts(page: 3)

      expect(stub).to have_been_requested
    end

    it 'returns definitions via #{name}_contract' do
      definition = client.list_posts_contract
      expect(definition).to be_a(Contractful::Contract::Definition)
      expect(definition.name).to eq :list_posts
    end

    it 'answers has_#{name}? predicates' do
      expect(client.has_list_posts?).to be true
      expect(client.has_nope?).to be false
    end

    it 'claims the dynamic methods via respond_to_missing?' do
      expect(client.respond_to?(:call_list_posts)).to be true
      expect(client.respond_to?(:list_posts_contract)).to be true
      expect(client.respond_to?(:has_list_posts?)).to be true
      expect(client.respond_to?(:has_nope?)).to be true # predicates always respond
      expect(client.respond_to?(:call_nope)).to be false
      expect(client.respond_to?(:nope_contract)).to be false
    end

    it 'raises NoMethodError for unknown methods' do
      expect { client.definitely_not_a_thing }.to raise_error(NoMethodError)
    end

    it 'lets real methods take precedence over the dynamic patterns' do
      klass = build_client do
        # A contract literally named call_ping: the generated method wins.
        contract(:call_ping, 'GET /ping')
      end

      expect(klass.new.respond_to?(:call_ping)).to be true
      expect(klass.new.method(:call_ping).owner).to eq klass
    end
  end
end
