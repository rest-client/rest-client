# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe 'Contractful::Contract response validation' do
  def build_client(&block)
    Class.new do
      include Contractful::Contract

      base 'https://api.test'
      instance_exec(&block)
    end
  end

  let(:client) { client_class.new }

  describe 'declared success statuses' do
    let(:client_class) do
      build_client do
        contract :list_posts, 'GET /posts' do
          responds 200
        end
      end
    end

    it 'returns the response when the status matches' do
      stub_request(:get, 'https://api.test/posts').to_return(status: 200, body: '[]')

      expect(client.list_posts).to be_a(Contractful::Response)
    end

    it 'raises UnexpectedResponse for a status outside the declared set' do
      stub_request(:get, 'https://api.test/posts').to_return(status: 204)

      expect do
        client.list_posts
      end.to raise_error(
        Contractful::Contract::UnexpectedResponse,
        %r{unexpected status 204 for GET /posts responds 200 \(expected 200\)}
      )
    end

    it 'attaches the offending response to the error' do
      stub_request(:get, 'https://api.test/posts').to_return(status: 204)

      begin
        client.list_posts
      rescue Contractful::Contract::UnexpectedResponse => e
        expect(e.response).to be_a(Contractful::Response)
        expect(e.response.code).to eq 204
      else
        raise 'expected the contract to raise'
      end
    end

    it 'accepts ranges as declared statuses' do
      client_class = build_client do
        contract :ping, 'GET /ping' do
          responds(200..299)
        end
      end

      stub_request(:get, 'https://api.test/ping').to_return(status: 204)

      expect(client_class.new.ping).to be_a(Contractful::Response)
    end
  end

  describe 'declared error statuses' do
    let(:client_class) do
      build_client do
        contract :show_widget, 'GET /widgets/:id' do
          param :id, Integer
          responds 200, 404
        end
      end
    end

    it 'returns declared 404 responses instead of raising ResourceNotFound' do
      stub_request(:get, 'https://api.test/widgets/7')
        .to_return(status: 404, body: '{"error":"missing"}')

      response = client_class.new.show_widget(id: 7)

      expect(response.code).to eq 404
    end

    it 'raises UnexpectedResponse for undeclared error statuses' do
      stub_request(:get, 'https://api.test/widgets/7').to_return(status: 500)

      expect do
        client_class.new.show_widget(id: 7)
      end.to raise_error(
        Contractful::Contract::UnexpectedResponse,
        %r{unexpected status 500 for GET /widgets/:id \(params: :id\) responds 200, 404 \(expected 200, 404\)}
      )
    end
  end

  describe 'default semantics without responds' do
    let(:client_class) do
      build_client do
        contract :show_widget, 'GET /widgets/:id' do
          param :id, Integer
        end
      end
    end

    it 'keeps contractful raising for error statuses' do
      stub_request(:get, 'https://api.test/widgets/7').to_return(status: 404)

      expect do
        client_class.new.show_widget(id: 7)
      end.to raise_error(Contractful::ResourceNotFound)
    end
  end

  describe 'redirects with declared error statuses' do
    let(:client_class) do
      build_client do
        contract :show_widget, 'GET /widgets/:id' do
          param :id, Integer
          responds 200, 404
        end
      end
    end

    it 'still follows redirects before validating' do
      stub_request(:get, 'https://api.test/widgets/7')
        .to_return(status: 302, headers: { 'Location' => 'https://api.test/widgets/8' })
      stub_request(:get, 'https://api.test/widgets/8').to_return(status: 404)

      response = client_class.new.show_widget(id: 7)

      expect(response.code).to eq 404
    end
  end

  describe 'response body types' do
    it 'validates Array bodies via JSON parsing' do
      client_class = build_client do
        contract :list_posts, 'GET /posts' do
          responds 200, type: Array
        end
      end
      stub_request(:get, 'https://api.test/posts').to_return(body: '[{"id":1}]')

      expect(client_class.new.list_posts).to be_a(Contractful::Response)
    end

    it 'raises UnexpectedResponse when the parsed body has the wrong shape' do
      client_class = build_client do
        contract :list_posts, 'GET /posts' do
          responds 200, type: :hash
        end
      end
      stub_request(:get, 'https://api.test/posts').to_return(body: '[1,2,3]')

      expect do
        client_class.new.list_posts
      end.to raise_error(
        Contractful::Contract::UnexpectedResponse,
        %r{response body does not match Hash for GET /posts}
      )
    end

    it 'raises UnexpectedResponse for non-JSON bodies when a type is declared' do
      client_class = build_client do
        contract :list_posts, 'GET /posts' do
          responds 200, type: Array
        end
      end
      stub_request(:get, 'https://api.test/posts').to_return(body: '<html>nope</html>')

      expect do
        client_class.new.list_posts
      end.to raise_error(
        Contractful::Contract::UnexpectedResponse,
        %r{response body is not valid JSON for GET /posts}
      )
    end

    it 'raises UnexpectedResponse for empty bodies when a type is declared' do
      client_class = build_client do
        contract :create_post, 'POST /posts' do
          param :title, String, required: true
          responds 201, type: :hash
        end
      end
      stub_request(:post, 'https://api.test/posts').to_return(status: 201, body: '')

      expect do
        client_class.new.create_post(title: 'Hi')
      end.to raise_error(
        Contractful::Contract::UnexpectedResponse,
        /expected Hash but the response body is empty/
      )
    end

    it 'passes raw bodies through for String types' do
      client_class = build_client do
        contract :readme, 'GET /readme' do
          responds 200, type: String
        end
      end
      stub_request(:get, 'https://api.test/readme').to_return(body: '# not json')

      expect(client_class.new.readme.body).to eq '# not json'
    end
  end

  describe 'verify_response blocks' do
    it 'accepts responses the block approves' do
      client_class = build_client do
        contract :list_posts, 'GET /posts' do
          responds 200
          verify_response { |response| response.headers[:x_flag] == 'yes' }
        end
      end
      stub_request(:get, 'https://api.test/posts')
        .to_return(body: '[]', headers: { 'X-Flag' => 'yes' })

      expect(client_class.new.list_posts).to be_a(Contractful::Response)
    end

    it 'raises UnexpectedResponse when the block rejects the response' do
      client_class = build_client do
        contract :list_posts, 'GET /posts' do
          responds 200
          verify_response { |response| response.headers[:x_flag] == 'yes' }
        end
      end
      stub_request(:get, 'https://api.test/posts')
        .to_return(body: '[]', headers: { 'X-Flag' => 'no' })

      expect do
        client_class.new.list_posts
      end.to raise_error(
        Contractful::Contract::UnexpectedResponse,
        %r{verify_response block rejected the response for GET /posts}
      )
    end

    it 'passes the JSON-parsed body to two-parameter blocks' do
      client_class = build_client do
        contract :list_posts, 'GET /posts' do
          responds 200
          verify_response { |_response, parsed| parsed.is_a?(Array) && parsed.size == 2 }
        end
      end
      stub_request(:get, 'https://api.test/posts').to_return(body: '[1,2]')

      expect(client_class.new.list_posts).to be_a(Contractful::Response)
    end

    it 'lets exceptions raised inside the block propagate' do
      client_class = build_client do
        contract :list_posts, 'GET /posts' do
          verify_response { |_response, _parsed| raise ArgumentError, 'boom' }
        end
      end
      stub_request(:get, 'https://api.test/posts').to_return(body: '{}')

      expect do
        client_class.new.list_posts
      end.to raise_error(ArgumentError, /boom/)
    end
  end

  describe 'definition-time validation' do
    it 'rejects responds without statuses' do
      expect do
        build_client { contract(:x, 'GET /x') { responds } }
      end.to raise_error(Contractful::Contract::InvalidDefinition, /responds requires at least one status/)
    end

    it 'rejects invalid statuses' do
      expect do
        build_client { contract(:x, 'GET /x') { responds 'ok' } }
      end.to raise_error(Contractful::Contract::InvalidDefinition, /invalid status "ok"/)
    end

    it 'rejects unsupported response types' do
      expect do
        build_client { contract(:x, 'GET /x') { responds 200, type: :yaml } }
      end.to raise_error(Contractful::Contract::InvalidDefinition, /unsupported response type :yaml/)
    end

    it 'rejects verify_response without a block' do
      client_class = build_client do
        contract :x, 'GET /x'
      end
      expect do
        client_class.__own_contract_config.contracts[:x].verify_response
      end.to raise_error(Contractful::Contract::InvalidDefinition, /verify_response requires a block/)
    end
  end

  describe 'introspection' do
    it 'includes response declarations in #describe' do
      definition = build_client do
        contract :show_widget, 'GET /widgets/:id' do
          param :id, Integer
          responds 200, 404, type: :hash
        end
      end.__own_contract_config.contracts[:show_widget]

      expect(definition.describe)
        .to eq 'GET /widgets/:id (params: :id) responds 200, 404 => Hash'
    end
  end
end
