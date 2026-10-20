# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe Contractful::Contract::Definition do
  def build(request_line = 'GET /posts', &block)
    verb, path = request_line.split(' ', 2)
    definition = described_class.new(:list_posts, verb, path)
    definition.instance_eval(&block) if block
    definition
  end

  it 'parses verb and path from the constructor arguments' do
    definition = described_class.new(:create_post, :post, '/posts')
    expect(definition.verb).to eq :post
    expect(definition.path_template).to eq '/posts'
    expect(definition.name).to eq :create_post
  end

  it 'rejects unsupported verbs' do
    expect do
      described_class.new(:x, :fetch, '/posts')
    end.to raise_error(Contractful::Contract::InvalidDefinition, /unsupported HTTP verb "fetch"/)
  end

  it 'rejects path templates that do not start with a slash' do
    expect do
      described_class.new(:x, :get, 'posts')
    end.to raise_error(Contractful::Contract::InvalidDefinition, %r{must start with "/"})
  end

  describe 'the DSL block' do
    it 'is instance_eval\'d against the definition' do
      definition = build('GET /posts') do
        param :page, Integer, default: 1
        payload_style :query
      end
      expect(definition.params.keys).to eq [:page]
      expect(definition.payload_style).to eq :query
    end

    it 'rejects invalid payload styles' do
      expect do
        build('POST /posts') { payload_style :carrier_pigeon }
      end.to raise_error(Contractful::Contract::InvalidDefinition, /invalid payload_style :carrier_pigeon/)
    end
  end

  describe 'path param synthesis' do
    it 'synthesizes required params for :placeholders' do
      definition = described_class.new(:show, :get, '/posts/:id/comments')
      expect(definition.path_param_names).to eq %i[id]
      expect(definition.params[:id]).to be_required
    end

    it 'does not clobber explicitly declared path params' do
      definition = described_class.new(:show, :get, '/posts/:id') do
        param :id, Integer
      end
      expect(definition.params[:id].type).to eq Integer
    end
  end

  describe '#expand_path' do
    it 'substitutes placeholders and returns the remaining params' do
      definition = described_class.new(:show, :get, '/repos/:owner/:repo/issues')
      path, remaining = definition.expand_path(owner: 'octo', repo: 'hi', page: 2)
      expect(path).to eq '/repos/octo/hi/issues'
      expect(remaining).to eq(page: 2)
    end

    it 'escapes unsafe characters in path segments' do
      definition = described_class.new(:show, :get, '/users/:name')
      path, = definition.expand_path(name: 'a b/c')
      expect(path).to eq '/users/a%20b%2Fc'
    end

    it 'raises MissingParam for placeholders without values' do
      definition = described_class.new(:show, :get, '/posts/:id')
      expect do
        definition.expand_path({})
      end.to raise_error(Contractful::Contract::MissingParam, /path param :id is required/)
    end
  end

  describe '#describe' do
    it 'renders verb, path and params' do
      definition = build('POST /repos/:owner/:repo/issues') do
        param :title, String, required: true
      end
      expect(definition.describe).to eq 'POST /repos/:owner/:repo/issues (params: :owner, :repo, :title)'
    end
  end
end
