# frozen_string_literal: true

require_relative '../../spec_helper'
require 'contractful/contract/openapi_import'
require 'tmpdir'

# Edge-branch coverage for the OpenAPI import: load failures, lossy-mapping
# notes not exercised elsewhere, and the renderer's defensive guarantees for
# hand-built definitions. Complements openapi_import_spec.rb.
RSpec.describe Contractful::Contract::OpenAPIImport do
  subject(:mod) { described_class }

  describe '.load' do
    it 'rejects unsupported sources' do
      expect { mod.load(42) }.to raise_error(
        mod::Error, /cannot load an OpenAPI document from 42/
      )
    end

    it 'reports invalid YAML with the file name' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'broken.yaml')
        File.write(path, "openapi: 3.0.3\n  bad:\n  - : : :")
        expect { mod.load(path) }.to raise_error(mod::Error, /invalid YAML in #{path}/)
      end
    end
  end

  describe '.import — lossy mapping notes' do
    it 'notes and skips trace operations' do
      d = { 'openapi' => '3.0.3', 'paths' => {
        '/w' => { 'trace' => { 'operationId' => 'traceIt', 'responses' => {} } }
      } }
      expect(mod.import(d).notes).to include(/trace operation skipped/)
    end

    it 'notes media-type parameters as not representable' do
      d = { 'openapi' => '3.0.3', 'paths' => {
        '/w' => { 'get' => {
          'parameters' => [{ 'name' => 'blob', 'in' => 'query',
                             'content' => { 'application/json' => {} } }],
          'responses' => {}
        } }
      } }
      expect(mod.import(d).notes).to include(/media-type parameter \(content\) is not representable/)
    end

    it 'notes operations that mix a request body with query parameters' do
      d = { 'openapi' => '3.0.3', 'paths' => {
        '/w' => { 'post' => {
          'parameters' => [{ 'name' => 'flag', 'in' => 'query',
                             'schema' => { 'type' => 'boolean' } }],
          'requestBody' => { 'content' => { 'application/json' => {
            'schema' => { 'type' => 'object' }
          } } },
          'responses' => {}
        } }
      } }
      expect(mod.import(d).notes).to include(/mixes a request body and query parameters/)
    end

    it 'notes and skips param names that are not valid Ruby identifiers' do
      d = { 'openapi' => '3.0.3', 'paths' => {
        '/w' => { 'get' => {
          'parameters' => [{ 'name' => 'X-Request-Id', 'in' => 'query',
                             'schema' => { 'type' => 'string' } }],
          'responses' => {}
        } }
      } }
      expect(mod.import(d).notes).to include(/name is not a valid Ruby identifier/)
    end
  end

  describe 'the renderer — hand-built definition guarantees' do
    def import_for(&block)
      client = Class.new { include Contractful::Contract }
      client.class_exec(&block)
      mod::Import.new(document: { 'openapi' => '3.0.3' }, base_url: 'https://api.test',
                      auth_hints: [], definitions: { weird: client.contract_for(:weird) }, notes: [])
    end

    it 'refuses to render a Proc default' do
      import = import_for do
        contract :weird, 'GET /x' do
          param :counted, Integer, default: -> { 1 }
        end
      end
      expect { import.to_ruby(class_name: 'GeneratedClient') }
        .to raise_error(mod::Error, /cannot render a Proc default for param :counted/)
    end

    it 'refuses to render a Proc param type' do
      import = import_for do
        contract :weird, 'GET /x' do
          param :shaped, lambda(&:to_i)
        end
      end
      expect { import.to_ruby(class_name: 'GeneratedClient') }
        .to raise_error(mod::Error, /cannot render a Proc param type/)
    end

    it 'can be required standalone without prior contractful requires' do
      cmd = [Gem.ruby, '-Ilib', '-rcontractful/contract/openapi_import', '-e', 'exit(0)']
      expect(system(*cmd)).to be(true)
    end
  end
end
