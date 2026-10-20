# frozen_string_literal: true

require_relative '../../spec_helper'
require 'contractful/contract/openapi_import'
require 'tmpdir'
require 'pathname'

RSpec.describe Contractful::Contract::OpenAPIImport do
  subject(:mod) { described_class }

  let(:user_schema) do
    {
      'type' => 'object',
      'required' => %w[id email],
      'properties' => {
        'id' => { 'type' => 'integer' },
        'email' => { 'type' => 'string' },
        'role' => { 'type' => 'string', 'enum' => %w[admin member] }
      }
    }
  end

  let(:doc) do
    {
      'openapi' => '3.0.3',
      'info' => { 'title' => 'Acme API', 'version' => '1.0.0' },
      'servers' => [{ 'url' => 'https://api.acme.test/v1' }],
      'components' => {
        'securitySchemes' => { 'bearerAuth' => { 'type' => 'http', 'scheme' => 'bearer' } },
        'schemas' => { 'User' => user_schema }
      },
      'paths' => {
        '/users' => {
          'get' => {
            'operationId' => 'listUsers',
            'parameters' => [
              { 'name' => 'page', 'in' => 'query',
                'schema' => { 'type' => 'integer', 'minimum' => 1, 'default' => 1 } },
              { 'name' => 'role', 'in' => 'query',
                'schema' => { 'type' => 'string', 'enum' => %w[admin member] } }
            ],
            'responses' => {
              '200' => { 'content' => { 'application/json' => { 'schema' => {
                'type' => 'array', 'items' => { '$ref' => '#/components/schemas/User' }
              } } } },
              '401' => { 'description' => 'unauthorized' }
            }
          },
          'post' => {
            'operationId' => 'createUser',
            'requestBody' => { 'content' => { 'application/json' => { 'schema' => {
              'type' => 'object', 'required' => ['email'],
              'properties' => {
                'email' => { 'type' => 'string' },
                'age' => { 'type' => 'integer', 'minimum' => 18 },
                'name' => { 'type' => 'string', 'minLength' => 2, 'maxLength' => 40 },
                'patterned' => { 'type' => 'string', 'pattern' => '\A[a-z]+\z' }
              }
            } } } },
            'responses' => {
              '201' => { 'content' => { 'application/json' => { 'schema' => {
                '$ref' => '#/components/schemas/User'
              } } } },
              '422' => { 'content' => { 'application/json' => { 'schema' => { 'type' => 'object' } } } }
            }
          }
        },
        '/users/{id}' => {
          'get' => {
            'summary' => 'Fetch one user',
            'parameters' => [
              { 'name' => 'id', 'in' => 'path', 'required' => true,
                'schema' => { 'type' => 'integer' } }
            ],
            'responses' => {
              '200' => { 'content' => { 'application/json' => { 'schema' => {
                '$ref' => '#/components/schemas/User'
              } } } },
              'default' => { 'description' => 'anything' }
            }
          }
        }
      }
    }
  end

  def definitions(source = doc, **opts)
    mod.definitions(source, **opts)
  end

  describe '.load' do
    it 'passes a Hash through' do
      expect(mod.load(doc)).to eq doc
    end

    it 'parses YAML text' do
      text = "openapi: 3.0.3\ninfo:\n  title: T\n  version: '1'\npaths: {}"
      expect(mod.load(text)).to include('openapi' => '3.0.3')
    end

    it 'parses JSON text' do
      expect(mod.load('{"openapi": "3.1.0"}')).to include('openapi' => '3.1.0')
    end

    it 'loads YAML and JSON files from a path string or Pathname' do
      Dir.mktmpdir do |dir|
        yaml_path = File.join(dir, 'api.yaml')
        json_path = File.join(dir, 'api.json')
        File.write(yaml_path, YAML.dump(doc))
        File.write(json_path, JSON.generate(doc))

        expect(mod.load(yaml_path)['info']).to eq doc['info']
        expect(mod.load(Pathname.new(json_path))['info']).to eq doc['info']
      end
    end

    it 'raises on a missing file' do
      expect { mod.load('/nonexistent/spec/openapi.yaml') }
        .to raise_error(mod::Error, /no such file/)
    end

    it 'raises on invalid YAML' do
      expect { mod.load("openapi: 3.0.3\n  bad:\n  - : : :") }
        .to raise_error(mod::Error, /invalid YAML/)
    end

    it 'raises on Swagger 2.x documents' do
      expect { definitions({ 'openapi' => '2.0', 'paths' => {} }) }
        .to raise_error(mod::Error, /convert the document to OpenAPI 3\.x/)
    end

    it 'raises on a missing or non-3.x version' do
      expect { definitions({ 'paths' => {} }) }
        .to raise_error(mod::Error, /missing or unsupported 'openapi' version/)
      expect { definitions({ 'openapi' => '4.0.0', 'paths' => {} }) }
        .to raise_error(mod::Error, /missing or unsupported/)
    end

    it 'raises when the document declares no paths' do
      expect { definitions({ 'openapi' => '3.0.3', 'paths' => {} }) }
        .to raise_error(mod::Error, /declares no paths/)
    end
  end

  describe '.definitions — naming' do
    it 'snake-cases operationIds' do
      expect(definitions.keys).to include(:list_users, :create_user)
    end

    it 'derives names from verb + path segments when operationId is absent' do
      expect(definitions.keys).to include(:get_users_id)
    end

    it 'collapses placeholder braces in derived names without double underscores' do
      expect(definitions[:get_users_id].path_template).to eq '/users/:id'
    end

    it 'deduplicates name collisions with a numeric suffix' do
      d = { 'openapi' => '3.0.3', 'paths' => {
        '/a' => { 'get' => { 'operationId' => 'doThing', 'responses' => {} } },
        '/b' => { 'get' => { 'operationId' => 'do-thing', 'responses' => {} } }
      } }
      expect(definitions(d).keys).to eq %i[do_thing do_thing_2]
    end

    it 'never produces reserved names' do
      d = { 'openapi' => '3.0.3', 'paths' => {
        '/x' => { 'get' => { 'operationId' => 'send', 'responses' => {} } }
      } }
      expect(definitions(d).keys).not_to include(:send)
    end

    it 'sanitizes characters that cannot appear in Ruby method names' do
      d = { 'openapi' => '3.0.3', 'paths' => {
        '/v2/orders history' => { 'get' => { 'operationId' => 'list.orders history!',
                                             'responses' => {} } }
      } }
      expect(definitions(d).keys).to include(:list_orders_history)
    end

    it 'raises on invalid path placeholders' do
      d = { 'openapi' => '3.0.3', 'paths' => {
        '/files/{file name}' => { 'get' => { 'responses' => {} } }
      } }
      expect { definitions(d) }.to raise_error(mod::Error, /not a valid Ruby identifier/)
    end

    it 'filters with only:/except: by final operation name' do
      expect(definitions(doc, only: [:list_users]).keys).to eq %i[list_users]
      expect(definitions(doc, except: %i[list_users create_user]).keys).to eq %i[get_users_id]
    end
  end

  describe '.definitions — params' do
    it 'maps query params with types, defaults, enums and constraints' do
      page = definitions[:list_users].params[:page]
      expect(page.type).to eq Integer
      expect(page.has_default?).to be true
      expect(page.default_value).to eq 1
      expect(page.min).to eq 1

      role = definitions[:list_users].params[:role]
      expect(role.type).to eq String
      expect(role.inclusion).to eq %w[admin member]
    end

    it 'declares path params explicitly (replacing the synthesized String param)' do
      param = definitions[:get_users_id].params[:id]
      expect(param.type).to eq Integer
      expect(param.required?).to be true
    end

    it 'shifts an exclusive integer bound by one' do
      d = { 'openapi' => '3.0.3',
            'paths' => {
              '/counts' => { 'get' => {
                'operationId' => 'getCounts',
                'parameters' => [{ 'name' => 'count', 'in' => 'query',
                                   'schema' => { 'type' => 'integer', 'exclusiveMinimum' => 5 } }],
                'responses' => {}
              } }
            } }

      import = mod.import(d)

      expect(import.definitions[:get_counts].params[:count].min).to eq 6
      expect(import.notes.join).not_to match(/exclusiveMinimum approximated/)
    end

    it 'does not shift an exclusive numeric bound for a number schema' do
      d = { 'openapi' => '3.0.3',
            'paths' => {
              '/ratios' => { 'get' => {
                'operationId' => 'getRatios',
                'parameters' => [{ 'name' => 'ratio', 'in' => 'query',
                                   'schema' => { 'type' => 'number', 'exclusiveMinimum' => 5 } }],
                'responses' => {}
              } }
            } }

      import = mod.import(d)
      param = import.definitions[:get_ratios].params[:ratio]

      expect(param.min).to eq 5
      expect(import.notes.join).to match(/exclusiveMinimum approximated as an inclusive bound/)
      expect { param.process!(5.5) }.not_to raise_error
    end

    it 'maps request body properties with required from the schema required array' do
      params = definitions[:create_user].params
      expect(params[:email].required?).to be true
      expect(params[:age].required?).to be false
      expect(params[:age].type).to eq Integer
      expect(params[:age].min).to eq 18
    end

    it 'maps minLength/maxLength to a length range and pattern to a Regexp' do
      name = definitions[:create_user].params[:name]
      expect(name.length).to eq(2..40)
      patterned = definitions[:create_user].params[:patterned]
      expect(patterned.pattern).to eq(/\A[a-z]+\z/)
    end

    it 'maps form-urlencoded request bodies to payload_style :form' do
      d = { 'openapi' => '3.0.3', 'paths' => {
        '/token' => { 'post' => {
          'requestBody' => { 'content' => {
            'application/x-www-form-urlencoded' => { 'schema' => {
              'type' => 'object',
              'properties' => { 'grant_type' => { 'type' => 'string' } }
            } }
          } },
          'responses' => {}
        } }
      } }
      expect(definitions(d)[:post_token].payload_style).to eq :form
    end

    it 'uses payload_style :query for body-less POST/PUT/PATCH with query params' do
      d = { 'openapi' => '3.0.3', 'paths' => {
        '/search' => { 'post' => {
          'parameters' => [{ 'name' => 'q', 'in' => 'query',
                             'schema' => { 'type' => 'string' } }],
          'responses' => {}
        } }
      } }
      expect(definitions(d)[:post_search].payload_style).to eq :query
    end

    it 'merges path-level and operation-level parameters (operation wins)' do
      d = { 'openapi' => '3.0.3', 'paths' => {
        '/items/{id}' => {
          'parameters' => [
            { 'name' => 'id', 'in' => 'path', 'schema' => { 'type' => 'string' } },
            { 'name' => 'verbose', 'in' => 'query', 'schema' => { 'type' => 'boolean' } }
          ],
          'get' => {
            'parameters' => [
              { 'name' => 'id', 'in' => 'path', 'schema' => { 'type' => 'integer' } }
            ],
            'responses' => {}
          }
        }
      } }
      params = definitions(d)[:get_items_id].params
      expect(params[:id].type).to eq Integer
      expect(params[:verbose].type).to eq :boolean
    end

    it 'resolves $ref parameters' do
      d = { 'openapi' => '3.0.3',
            'components' => { 'parameters' => {
              'PageParam' => { 'name' => 'page', 'in' => 'query',
                               'schema' => { 'type' => 'integer' } }
            } },
            'paths' => {
              '/logs' => { 'get' => {
                'parameters' => [{ '$ref' => '#/components/parameters/PageParam' }],
                'responses' => {}
              } }
            } }
      expect(definitions(d)[:get_logs].params[:page].type).to eq Integer
    end

    it 'resolves nested $ref schemas in params' do
      d = { 'openapi' => '3.0.3',
            'components' => { 'schemas' => {
              'Limit' => { 'type' => 'integer', 'maximum' => 100 }
            } },
            'paths' => {
              '/things' => { 'get' => {
                'parameters' => [{ 'name' => 'limit', 'in' => 'query',
                                   'schema' => { '$ref' => '#/components/schemas/Limit' } }],
                'responses' => {}
              } }
            } }
      expect(definitions(d)[:get_things].params[:limit].max).to eq 100
    end
  end

  describe '.definitions — responses' do
    it 'collects statuses sorted and derives the body type from the first 2xx JSON schema' do
      d = definitions[:list_users]
      expect(d.response_statuses).to eq [200, 401]
      expect(d.response_type).to eq Array
    end

    it 'maps object responses to Hash with open-schema response fields from $refs' do
      d = definitions[:create_user]
      expect(d.response_type).to eq Hash
      expect(d.response_fields.keys).to eq %i[id email role]
      expect(d.response_fields[:id].required?).to be true
      expect(d.response_fields[:id].type).to eq Integer
      expect(d.response_fields[:role].required?).to be false
      expect(d.response_fields[:role].inclusion).to eq %w[admin member]
      expect(d.response_fields[:role]).not_to be_strict
    end

    it 'maps 2XX wildcards to a Range' do
      d = { 'openapi' => '3.0.3', 'paths' => {
        '/anything' => { 'get' => {
          'responses' => { '2XX' => { 'content' => { 'application/json' => {
            'schema' => { 'type' => 'object' }
          } } } }
        } }
      } }
      definition = definitions(d)[:get_anything]
      expect(definition.response_statuses).to eq [(200..299)]
      expect(definition.response_type).to eq Hash
    end

    it 'notes and skips the default response' do
      import = mod.import(doc)
      expect(import.notes).to include(/response "default": the 'default' response is not representable/)
      expect(definitions[:get_users_id].response_statuses).to eq [200]
    end

    it 'derives type :json for JSON bodies without a resolvable shape' do
      d = { 'openapi' => '3.0.3', 'paths' => {
        '/blob' => { 'get' => {
          'responses' => { '200' => { 'content' => { 'application/json' => {} } } }
        } }
      } }
      expect(definitions(d)[:get_blob].response_type).to eq :json
    end

    it 'keeps string responses as String with no response fields' do
      d = { 'openapi' => '3.0.3', 'paths' => {
        '/health' => { 'get' => {
          'responses' => { '200' => { 'content' => { 'application/json' => {
            'schema' => { 'type' => 'string' }
          } } } }
        } }
      } }
      definition = definitions(d)[:get_health]
      expect(definition.response_type).to eq String
      expect(definition.response_fields).to be_empty
    end
  end

  describe 'the notes channel' do
    it 'reports header and cookie params as not representable' do
      d = { 'openapi' => '3.0.3', 'paths' => {
        '/w' => { 'get' => {
          'parameters' => [
            { 'name' => 'X-Request-Id', 'in' => 'header', 'schema' => { 'type' => 'string' } },
            { 'name' => 'sid', 'in' => 'cookie', 'schema' => { 'type' => 'string' } }
          ],
          'responses' => {}
        } }
      } }
      notes = mod.import(d).notes
      expect(notes).to include(/header param "X-Request-Id": header parameters are not representable/)
      expect(notes).to include(/cookie param "sid": cookie parameters are not representable/)
    end

    it 'reports multipart and non-JSON bodies' do
      d = { 'openapi' => '3.0.3', 'paths' => {
        '/upload' => { 'post' => {
          'requestBody' => { 'content' => { 'multipart/form-data' => {
            'schema' => { 'type' => 'object',
                          'properties' => { 'file' => { 'type' => 'string', 'format' => 'binary' } } }
          } } },
          'responses' => {}
        } }
      } }
      expect(mod.import(d).notes).to include(%r{multipart/form-data.*not representable as contract params})
    end

    it 'reports oneOf unions instead of guessing' do
      d = { 'openapi' => '3.0.3', 'paths' => {
        '/pay' => { 'post' => {
          'requestBody' => { 'content' => { 'application/json' => {
            'schema' => { 'oneOf' => [{ 'type' => 'object' }, { 'type' => 'array' }] }
          } } },
          'responses' => {}
        } }
      } }
      expect(mod.import(d).notes).to include(%r{schema combination \(oneOf/anyOf/allOf\)})
      expect(definitions(d)[:post_pay].params).to be_empty
    end

    it 'reports mixed query params on body verbs' do
      d = { 'openapi' => '3.0.3', 'paths' => {
        '/orders' => { 'post' => {
          'parameters' => [{ 'name' => 'dry_run', 'in' => 'query',
                             'schema' => { 'type' => 'boolean' } }],
          'requestBody' => { 'content' => { 'application/json' => {
            'schema' => { 'type' => 'object', 'properties' => { 'qty' => { 'type' => 'integer' } } }
          } } },
          'responses' => {}
        } }
      } }
      notes = mod.import(d).notes
      expect(notes).to include(/mixes a request body and query parameters/)
      expect(definitions(d)[:post_orders].params[:dry_run]).not_to be_nil
    end

    it 'reports deprecated operations and unsupported status spellings' do
      d = { 'openapi' => '3.0.3', 'paths' => {
        '/old' => { 'get' => {
          'deprecated' => true,
          'responses' => { 'OK' => { 'description' => 'fine' } }
        } }
      } }
      notes = mod.import(d).notes
      expect(notes).to include(%r{GET /old: deprecated operation})
      expect(notes).to include(/response code "OK" is not a numeric status/)
    end

    it 'does not invent base URLs for relative servers' do
      d = { 'openapi' => '3.0.3',
            'servers' => [{ 'url' => '/api/v1' }],
            'paths' => { '/x' => { 'get' => { 'responses' => {} } } } }
      import = mod.import(d)
      expect(import.base_url).to be_nil
      expect(import.notes).to include(/not an absolute http\(s\) URL/)
    end

    it 'reports unresolvable refs and keeps the param untyped' do
      d = { 'openapi' => '3.0.3', 'paths' => {
        '/x' => { 'get' => {
          'parameters' => [{ 'name' => 'q', 'in' => 'query',
                             'schema' => { '$ref' => '#/components/schemas/Missing' } }],
          'responses' => {}
        } }
      } }
      import = mod.import(d)
      expect(import.notes.join).to match(/unresolvable \$ref/)
      expect(import.definitions[:get_x].params[:q].type).to be_nil
    end

    it 'deduplicates repeated notes' do
      d = { 'openapi' => '3.0.3', 'paths' => {
        '/a' => { 'get' => { 'parameters' => [
          { 'name' => 'sid', 'in' => 'cookie', 'schema' => { 'type' => 'string' } }
        ], 'responses' => {} } },
        '/b' => { 'get' => { 'parameters' => [
          { 'name' => 'sid', 'in' => 'cookie', 'schema' => { 'type' => 'string' } }
        ], 'responses' => {} } }
      } }
      cookie_notes = mod.import(d).notes.grep(/cookie param "sid"/)
      expect(cookie_notes.size).to eq 2 # distinct labels stay distinct
    end
  end

  describe 'base URL and auth hints' do
    it 'takes the first server URL' do
      expect(mod.import(doc).base_url).to eq 'https://api.acme.test/v1'
    end

    it 'substitutes server variables with their defaults' do
      d = { 'openapi' => '3.0.3', 'servers' => [{
        'url' => 'https://{region}.acme.test/v1',
        'variables' => { 'region' => { 'default' => 'us' } }
      }], 'paths' => { '/x' => { 'get' => { 'responses' => {} } } } }
      expect(mod.import(d).base_url).to eq 'https://us.acme.test/v1'
    end

    it 'emits auth hints for bearer, basic and apiKey schemes' do
      d = { 'openapi' => '3.0.3',
            'components' => { 'securitySchemes' => {
              'b' => { 'type' => 'http', 'scheme' => 'bearer' },
              'ba' => { 'type' => 'http', 'scheme' => 'basic' },
              'key' => { 'type' => 'apiKey', 'in' => 'header', 'name' => 'X-Api-Key' },
              'qkey' => { 'type' => 'apiKey', 'in' => 'query', 'name' => 'api_token' }
            } },
            'paths' => { '/x' => { 'get' => { 'responses' => {} } } } }
      hints = mod.import(d).auth_hints
      expect(hints.grep(/auth bearer:/).first).to include("ENV['B_TOKEN']")
      expect(hints.grep(/auth basic:/).first).to include("ENV['BA_USER']")
      expect(hints.grep(/auth api_key:/).first).to include('"X-Api-Key"')
      expect(hints.grep(/in: :query/).first).to include('"api_token"')
    end

    it 'notes OAuth schemes instead of faking them' do
      d = { 'openapi' => '3.0.3',
            'components' => { 'securitySchemes' => {
              'oa' => { 'type' => 'oauth2', 'flows' => {} }
            } },
            'paths' => { '/x' => { 'get' => { 'responses' => {} } } } }
      expect(mod.import(d).notes.join).to match(/OAuth flows are not auto-generated/)
    end
  end

  describe '.to_ruby — generated source round-trips' do
    let(:class_token) { "G#{object_id.abs}" }
    let(:source) { mod.to_ruby(doc, class_name: "Acme::#{class_token}") }
    let(:generated) do
      Object.send(:remove_const, :Acme) if Object.const_defined?(:Acme, false)
      Object.const_set(:Acme, Module.new)
      TOPLEVEL_BINDING.eval(source)
      Acme.const_get(class_token)
    end

    it 'renders valid Ruby for every imported definition' do
      expect(source).to include('base "https://api.acme.test/v1"')
      expect(source).to include('contract :list_users, "GET /users" do')
      expect(source).to include('param :page, Integer, default: 1, min: 1')
      expect(source).to include('responds 200, 401, type: :array')
      expect(source).to include('response_field :id, :integer, required: true')
      expect(source).to include('# auth bearer: -> {')
    end

    it 'evaluates to a client class whose contracts describe identically (round-trip)' do
      imported = definitions
      expect(imported.keys).to eq generated.contract_names
      imported.each do |name, definition|
        expect(generated.contract_for(name).describe).to eq definition.describe
      end
    end

    it 'emits import notes as comments' do
      expect(source).to include('# Import notes (review these):')
      expect(source).to include('#   - GET /users/{id} response "default":')
    end

    it 'rejects invalid class names' do
      expect { mod.to_ruby(doc, class_name: 'not-a-constant') }
        .to raise_error(mod::Error, /class_name must be a Ruby constant/)
    end
  end

  describe 'generated clients execute end-to-end' do
    let(:class_name) { "ImportSmoke#{object_id.abs}" }
    let(:source) do
      <<~RUBY
        class #{class_name}
          include Contractful::Contract
          base 'https://smoke.test'
          contract :list_users, 'GET /users' do
            param :page, Integer, default: 1, min: 1
            responds 200, 401, type: :array
          end
        end
      RUBY
    end

    before { TOPLEVEL_BINDING.eval(source) }

    it 'executes a mapped contract through WebMock' do
      stub_request(:get, 'https://smoke.test/users')
        .with(query: hash_including('page' => '1'))
        .to_return(body: '[{"id":1,"email":"a@b.c"}]',
                   headers: { 'Content-Type' => 'application/json' })

      response = Object.const_get(class_name).new.list_users
      expect(response.json).to eq([{ 'id' => 1, 'email' => 'a@b.c' }])
    end

    it 'rejects invalid params before any network traffic' do
      expect { Object.const_get(class_name).new.list_users(page: 0) }
        .to raise_error(Contractful::Contract::InvalidParam, /below minimum 1/)
      expect(a_request(:any, //)).not_to have_been_made
    end
  end
end
