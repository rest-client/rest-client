# frozen_string_literal: true

require_relative '../../spec_helper'

RSpec.describe 'Contractful::Contract pagination' do
  def build_client(&block)
    Class.new do
      include Contractful::Contract

      instance_exec(&block)
    end
  end

  describe 'cursor style' do
    let(:client_class) do
      build_client do
        base 'https://api.test'

        contract :list_orders, 'GET /orders' do
          param :pageToken, String
          param :pageSize, Integer, default: 2

          paginated style: :cursor, cursor_param: :pageToken,
                    next_cursor_path: 'nextPageToken', items_path: 'orders'
        end
      end
    end

    let(:client) { client_class.new }

    def stub_page(token, orders, next_token)
      body = { orders: orders, nextPageToken: next_token }.compact
      query = token.nil? ? { 'pageSize' => '2' } : { 'pageSize' => '2', 'pageToken' => token }
      stub_request(:get, 'https://api.test/orders')
        .with(query: hash_including(query))
        .to_return(body: JSON.generate(body))
    end

    before do
      stub_page(nil, %w[o1 o2], 't1')
      stub_page('t1', %w[o3 o4], 't2')
      stub_page('t2', %w[o5], nil)
    end

    it 'walks every page and yields validated responses' do
      pages = client.list_orders_pages.to_a
      expect(pages.length).to eq 3
      expect(pages.map(&:code).uniq).to eq [200]
    end

    it 'passes the next cursor from each page into the following request' do
      client.list_orders_pages.to_a

      expect(a_request(:get, 'https://api.test/orders')
        .with(query: hash_including('pageToken' => 't1'))).to have_been_made.once
      expect(a_request(:get, 'https://api.test/orders')
        .with(query: hash_including('pageToken' => 't2'))).to have_been_made.once
    end

    it 'resumes from an explicitly supplied cursor' do
      client.list_orders_pages(pageToken: 't2').to_a
      expect(a_request(:get, 'https://api.test/orders')
        .with(query: hash_including('pageToken' => 't2'))).to have_been_made.once
    end

    it 'collects all items flat across pages' do
      expect(client.all_list_orders).to eq %w[o1 o2 o3 o4 o5]
    end

    it 'is lazy: taking fewer pages makes fewer requests' do
      client.list_orders_pages.take(1)
      expect(a_request(:get, 'https://api.test/orders')
        .with(query: hash_including('pageSize' => '2'))).to have_been_made.once
    end

    it 'still validates each page against the contract' do
      stub_request(:get, 'https://api.test/orders')
        .with(query: hash_including('pageSize' => '2'))
        .to_return(status: 404)

      expect { client.list_orders_pages.to_a }
        .to raise_error(Contractful::NotFound)
    end

    it 'stops when the next cursor is empty' do
      stub_request(:get, 'https://api.test/orders')
        .with(query: hash_including('pageSize' => '2'))
        .to_return(body: JSON.generate(orders: %w[o1], nextPageToken: ''))

      pages = client.list_orders_pages.to_a
      expect(pages.length).to eq 1
    end
  end

  describe 'offset style' do
    let(:client_class) do
      build_client do
        base 'https://api.test'

        contract :list_positions, 'GET /positions' do
          param :offset, Integer, default: 0
          param :limit, Integer, default: 2

          paginated style: :offset, offset_param: :offset, limit_param: :limit,
                    items_path: 'data.positions', has_more_path: 'hasMore'
        end
      end
    end

    let(:client) { client_class.new }

    def stub_offset(offset, positions, has_more)
      stub_request(:get, 'https://api.test/positions')
        .with(query: hash_including('offset' => offset.to_s, 'limit' => '2'))
        .to_return(body: JSON.generate(data: { positions: positions }, hasMore: has_more))
    end

    before do
      stub_offset(0, %w[p1 p2], true)
      stub_offset(2, %w[p3], false)
    end

    it 'advances the offset and honors has_more' do
      expect(client.all_list_positions).to eq %w[p1 p2 p3]

      expect(a_request(:get, 'https://api.test/positions')
        .with(query: hash_including('offset' => '0'))).to have_been_made.once
      expect(a_request(:get, 'https://api.test/positions')
        .with(query: hash_including('offset' => '2'))).to have_been_made.once
    end

    it 'digs nested items paths' do
      pages = client.list_positions_pages.to_a
      expect(pages.length).to eq 2
    end
  end

  describe 'stop conditions and guards' do
    it 'stops on an empty page when no has_more_path is declared' do
      client_class = build_client do
        base 'https://api.test'
        contract :list_rows, 'GET /rows' do
          param :offset, Integer, default: 0
          paginated style: :offset, offset_param: :offset
        end
      end

      stub_request(:get, 'https://api.test/rows')
        .with(query: hash_including('offset' => '0'))
        .to_return(body: JSON.generate(%w[r1 r2]))
      stub_request(:get, 'https://api.test/rows')
        .with(query: hash_including('offset' => '2'))
        .to_return(body: JSON.generate([]))

      expect(client_class.new.all_list_rows).to eq %w[r1 r2]
    end

    it 'raises PaginationError after exceeding the page limit' do
      client_class = build_client do
        base 'https://api.test'
        contract :list_forever, 'GET /forever' do
          param :pageToken, String
          paginated style: :cursor, cursor_param: :pageToken,
                    next_cursor_path: 'next', items_path: 'items'
        end
      end

      stub_request(:get, 'https://api.test/forever')
        .to_return(body: JSON.generate(items: ['x'], next: 'more'))
      stub_request(:get, 'https://api.test/forever')
        .with(query: hash_including('pageToken' => 'more'))
        .to_return(body: JSON.generate(items: ['x'], next: 'more'))

      expect do
        client_class.new.list_forever_pages(_max_pages: 3).to_a
      end.to raise_error(
        Contractful::Contract::PaginationError,
        /exceeded 3 pages.*_max_pages/
      )
    end

    it 'raises when items cannot be extracted without an items_path' do
      client_class = build_client do
        base 'https://api.test'
        contract :list_things, 'GET /things' do
          param :pageToken, String
          paginated style: :cursor, cursor_param: :pageToken,
                    next_cursor_path: 'next'
        end
      end

      stub_request(:get, 'https://api.test/things')
        .to_return(body: JSON.generate(items: %w[a], next: nil))

      expect do
        client_class.new.all_list_things
      end.to raise_error(Contractful::Contract::PaginationError, /declare items_path/)
    end

    it 'raises on non-array items' do
      client_class = build_client do
        base 'https://api.test'
        contract :list_bad, 'GET /bad' do
          param :pageToken, String
          paginated style: :cursor, cursor_param: :pageToken,
                    next_cursor_path: 'next', items_path: 'items'
        end
      end

      stub_request(:get, 'https://api.test/bad')
        .to_return(body: JSON.generate(items: 'not-an-array', next: nil))

      expect do
        client_class.new.all_list_bad
      end.to raise_error(Contractful::Contract::PaginationError, /expected Array/)
    end
  end

  describe 'definition-time validation' do
    it 'requires a style' do
      expect do
        build_client do
          base 'https://api.test'
          contract :x, 'GET /x' do
            paginated
          end
        end
      end.to raise_error(Contractful::Contract::InvalidDefinition, /requires a style/)
    end

    it 'requires cursor keys for the cursor style' do
      expect do
        build_client do
          base 'https://api.test'
          contract :x, 'GET /x' do
            paginated style: :cursor
          end
        end
      end.to raise_error(Contractful::Contract::InvalidDefinition, /requires :cursor_param/)
    end

    it 'requires offset_param for the offset style' do
      expect do
        build_client do
          base 'https://api.test'
          contract :x, 'GET /x' do
            paginated style: :offset
          end
        end
      end.to raise_error(Contractful::Contract::InvalidDefinition, /requires :offset_param/)
    end

    it 'rejects unknown styles' do
      expect do
        build_client do
          base 'https://api.test'
          contract :x, 'GET /x' do
            paginated style: :hyper
          end
        end
      end.to raise_error(Contractful::Contract::InvalidDefinition, /unknown pagination style/)
    end

    it 'marks paginated contracts in introspection' do
      client_class = build_client do
        base 'https://api.test'
        contract :list_orders, 'GET /orders' do
          param :pageToken, String
          paginated style: :cursor, cursor_param: :pageToken,
                    next_cursor_path: 'next'
        end
        contract :get_order, 'GET /orders/:id' do
          param :id, String, required: true
        end
      end

      expect(client_class.contract_for(:list_orders).pagination[:style]).to eq :cursor
      expect(client_class.contract_for(:list_orders).describe).to include('paginated')
      expect(client_class.contract_for(:get_order).pagination).to be_nil
    end
  end

  describe 'Pagination helpers' do
    it 'digs dotted paths through string and symbol keys' do
      data = { 'data' => { orders: %w[a] } }
      expect(Contractful::Contract::Pagination.dig(data, 'data.orders')).to eq %w[a]
      expect(Contractful::Contract::Pagination.dig(data, 'data.missing')).to be_nil
      expect(Contractful::Contract::Pagination.dig(data, nil)).to be_nil
    end
  end
end
