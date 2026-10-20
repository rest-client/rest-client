# frozen_string_literal: true

require 'json'

module Contractful
  module Contract
    # Raised when paginating a contract goes wrong: too many pages, an
    # unparseable page body, or items that cannot be extracted.
    class PaginationError < Error; end

    # Pagination engine for contracts declared with `paginated`.
    #
    # Two styles are supported:
    #
    #   * +:cursor+ — the server returns an opaque cursor for the next page
    #     (page token style):
    #
    #       paginated style: :cursor, cursor_param: :pageToken,
    #                        next_cursor_path: 'nextPageToken',
    #                        items_path: 'orders'
    #
    #   * +:offset+ — classic limit/offset paging; iteration stops when the
    #     declared +has_more_path+ is false, or when a page comes back empty:
    #
    #       paginated style: :offset, offset_param: :offset,
    #                        limit_param: :limit, items_path: 'data'
    #
    # For every paginated contract the client class gets two generated
    # methods (the pagination params themselves must be declared as regular
    # contract params):
    #
    #   client.list_orders_pages      # Enumerator of validated page responses
    #   client.all_list_orders        # flat Array of every item across pages
    #
    # Both accept the same params as the underlying contract, including the
    # meta options (+_max_retries+, ...) and a +_max_pages:+ safety limit
    # (default 1000) that raises {PaginationError} when exceeded — a missing
    # stop condition must not become an infinite request loop.
    module Pagination
      DEFAULT_MAX_PAGES = 1000

      CURSOR_KEYS = %i[cursor_param next_cursor_path].freeze
      OFFSET_KEYS = %i[offset_param].freeze

      module_function

      # Validate and normalize the `paginated` DSL options at definition
      # time, so a misconfigured pagination fails when the class loads.
      def normalize!(options)
        style = options[:style] ||
                raise(InvalidDefinition,
                      'paginated requires a style: (:cursor or :offset)')
        style = style.to_sym

        keys = case style
               when :cursor then CURSOR_KEYS
               when :offset then OFFSET_KEYS
               else
                 raise InvalidDefinition,
                       "unknown pagination style #{style.inspect} " \
                       '(expected :cursor or :offset)'
               end
        keys.each do |key|
          unless options[key]
            raise InvalidDefinition,
                  "paginated style #{style.inspect} requires #{key.inspect}"
          end
        end

        {
          style: style,
          cursor_param: options[:cursor_param]&.to_sym,
          next_cursor_path: options[:next_cursor_path],
          offset_param: options[:offset_param]&.to_sym,
          limit_param: options[:limit_param]&.to_sym,
          items_path: options[:items_path],
          has_more_path: options[:has_more_path]
        }.freeze
      end

      # Enumerator of page responses (each already validated by the
      # contract's response declaration).
      def each_page(instance, definition, params, &block)
        return enum_for(:each_page, instance, definition, params) unless block

        each_parsed(instance, definition, params) do |response, _parsed|
          yield response
        end
      end

      # Flat Array of every item across every page.
      def all_items(instance, definition, params)
        result = []
        each_parsed(instance, definition, params) do |_response, parsed|
          items = extract_items(parsed, definition.pagination, definition)
          unless items.is_a?(Array)
            raise PaginationError,
                  "items at #{definition.pagination[:items_path].inspect} are " \
                  "#{items.class}, expected Array for #{definition.describe}"
          end
          result.concat(items)
        end
        result
      end

      # Core loop: calls the contract page by page, injecting the cursor or
      # advancing the offset, validating every page through the contract.
      def each_parsed(instance, definition, params, &block)
        return enum_for(:each_parsed, instance, definition, params) unless block

        pagination = definition.pagination
        params = params.dup
        max_pages = params.delete(:_max_pages) || DEFAULT_MAX_PAGES
        unless max_pages.is_a?(Integer) && max_pages.positive?
          raise PaginationError,
                ":_max_pages must be a positive Integer, got #{max_pages.inspect}"
        end

        # Resume support: an explicitly supplied cursor/offset drives page 1.
        resume = if pagination[:style] == :cursor
                   params.delete(pagination[:cursor_param])
                 else
                   params.delete(pagination[:offset_param])
                 end

        pages = 0
        loop do
          pages += 1
          if pages > max_pages
            raise PaginationError,
                  "exceeded #{max_pages} pages for #{definition.describe} " \
                  '(pass _max_pages: to raise the limit, or check the ' \
                  'stop condition)'
          end

          call_params = params.dup
          if pagination[:style] == :cursor
            call_params[pagination[:cursor_param]] = resume unless resume.nil?
          else
            call_params[pagination[:offset_param]] = resume unless resume.nil?
          end

          response = Executor.call(instance, definition, call_params)
          parsed = parse_json(response, definition)
          items = extract_items(parsed, pagination, definition)

          yield response, parsed

          break unless continue?(pagination, parsed, items)

          resume = if pagination[:style] == :cursor
                     dig(parsed, pagination[:next_cursor_path])
                   else
                     (resume || 0) + items.length
                   end
        end
      end

      def continue?(pagination, parsed, items)
        if pagination[:has_more_path]
          has_more = dig(parsed, pagination[:has_more_path])
          return false unless has_more

          return true
        end

        if pagination[:style] == :cursor
          # Continue while the server hands out a non-empty next cursor.
          cursor = dig(parsed, pagination[:next_cursor_path])
          return !(cursor.nil? || cursor == '')
        end

        # Offset without has_more: stop when a page comes back empty.
        !items.empty?
      end

      # Extract items from a parsed page body. Without an items_path the
      # body itself must be the collection (a bare JSON Array).
      def extract_items(parsed, pagination, definition)
        path = pagination[:items_path]
        if path
          items = dig(parsed, path)
          items.nil? ? [] : items
        elsif parsed.is_a?(Array)
          parsed
        else
          raise PaginationError,
                "cannot extract items from #{parsed.class} for " \
                "#{definition.describe} — declare items_path: in paginated"
        end
      end

      # Parse a page body as JSON.
      def parse_json(response, definition)
        JSON.parse(response.body)
      rescue JSON::ParserError, TypeError => e
        raise PaginationError,
              "page body is not valid JSON for #{definition.describe}: #{e.message}"
      end

      # Traverse a dotted path ('data.orders') through String- and
      # Symbol-keyed hashes.
      def dig(data, dotted_path)
        return nil unless dotted_path

        dotted_path.to_s.split('.').reduce(data) do |acc, key|
          break nil if acc.nil? || !acc.is_a?(Hash)

          if acc.key?(key)
            acc[key]
          else
  (acc.key?(key.to_sym) ? acc[key.to_sym] : nil)
          end
        end
      end
    end
  end
end
