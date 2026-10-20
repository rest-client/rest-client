# frozen_string_literal: true

require 'yaml'
require 'json'
require_relative '../contract'

module Contractful
  module Contract
    # Recorded-sequence test helper (REQ-N02) — the testing counterpart to
    # the contract layer.
    #
    # Contracts deliberately do NOT express ordering, timing or cross-call
    # state machines. This helper closes that gap: a sequence fixture (a
    # YAML/JSON file under the consumer's control, or a Hash) drives a
    # contract client through N recorded interactions with WebMock, and the
    # run fails on the FIRST contract violation with the step number
    # attached.
    #
    #   require 'contractful/contract/sequence'   # test-only, opt-in
    #
    #   sequence = Contractful::Contract::Sequence.load(client, 'order_lifecycle.yml')
    #   sequence.after_step do |index, step, response|
    #     # stateful rules: token refresh, rate-limit windows, ...
    #   end
    #   sequence.run   # => [#<Result step 1>, ...] or raises Sequence::Failure
    #
    # Fixture shape:
    #
    #   name: order lifecycle
    #   steps:
    #     - call: create_order
    #       params: { quantity: 10 }
    #       response: { status: 201, body: { order_id: 'o-1' } }
    #     - call: get_order
    #       params: { order_id: 'o-1' }
    #       response: { status: 200, body: { order_id: 'o-1' } }
    #       expect_request:                     # optional outgoing assertions
    #         path: /orders/o-1
    #         query_include: { verbose: 'true' }
    #         headers_include: { X-Custom: v }
    #         json_include: { quantity: 10 }
    #
    # Each step stubs its recorded response (via WebMock), invokes the
    # contract method, and lets the contract's own response validation run:
    # a recorded response the contract does not declare is a violation at
    # that step. Request assertions verify the OUTGOING side too, so a
    # fixture can pin ordering-sensitive details (query params, headers,
    # payload subsets).
    module Sequence
      # Raised when WebMock is missing or disabled.
      class Error < Contractful::Contract::Error; end

      # Raised at load time when a fixture violates the schema (unknown
      # contract names, malformed steps, unknown assertion keys).
      class InvalidFixture < Error; end

      # Raised at run time on the first violated step. +step+ is the
      # 1-based step number, +call+ the contract name, +cause+ the original
      # exception (contract violation, HTTP error, failed assertion or hook
      # failure).
      class Failure < Error
        attr_reader :step, :call, :cause

        def initialize(step, call, cause = nil, message = nil)
          @step = step
          @call = call
          @cause = cause
          detail = message || cause&.message || cause&.class&.name
          super("step #{step} (#{call}): #{detail}")
        end
      end

      # One executed step.
      Result = Struct.new(:step, :call, :params, :response, :request, keyword_init: true)

      KNOWN_ASSERTIONS = %i[path query_include headers_include json_include].freeze

      module_function

      # Load a fixture (path or Hash) against a client and validate it.
      #
      # @param client a contract client instance (includes Contractful::Contract)
      # @param source [String, Pathname, Hash] fixture path or parsed fixture
      # @return [Player]
      def load(client, source)
        fixture = source.is_a?(Hash) ? deep_symbolize(source) : parse_fixture(source)
        steps = validate_fixture!(fixture, client)
        Player.new(client, fixture[:name], steps)
      end

      # Convenience: load + run.
      #
      # @return [Array<Result>]
      def run(client, source, &hook_block)
        player = load(client, source)
        player.after_step(&hook_block) if hook_block
        player.run
      end

      def parse_fixture(source)
        text = source.respond_to?(:read) ? source.read : File.read(source.to_s)
        deep_symbolize(YAML.safe_load(text, aliases: true) ||
                       raise(InvalidFixture, 'empty fixture'))
      rescue Psych::SyntaxError => e
        raise InvalidFixture, "invalid YAML fixture: #{e.message}"
      rescue Errno::ENOENT
        raise InvalidFixture, "no such fixture file: #{source}"
      end

      def validate_fixture!(fixture, client)
        unless fixture.is_a?(Hash) && fixture[:steps].is_a?(Array)
          raise InvalidFixture,
                "fixture must be a Hash with a 'steps' array, got #{fixture.class}"
        end
        raise InvalidFixture, 'fixture declares no steps' if fixture[:steps].empty?

        fixture[:steps].each_with_index do |raw, index|
          step = index + 1
          raise InvalidFixture, "step #{step}: every step needs a 'call'" unless raw.is_a?(Hash) && raw[:call]

          call = raw[:call].to_sym
          unless client.class.contract?(call)
            raise InvalidFixture,
                  "step #{step}: #{call.inspect} is not a contract on " \
                  "#{client.class}"
          end

          response = raw[:response]
          unless response.is_a?(Hash)
            raise InvalidFixture,
                  "step #{step} (#{call}): a 'response' Hash is required — " \
                  'record what the vendor actually returned'
          end
          status = response.fetch(:status, 200)
          unless status.is_a?(Integer) && (100..599).cover?(status)
            raise InvalidFixture,
                  "step #{step} (#{call}): response status must be an " \
                  "Integer in 100..599, got #{status.inspect}"
          end

          assert_fixture(response[:body], step, call, 'response body')

          next unless (expected = raw[:expect_request])
          unless expected.is_a?(Hash)
            raise InvalidFixture,
                  "step #{step} (#{call}): expect_request must be a Hash"
          end
          unknown = expected.keys.map(&:to_sym) - KNOWN_ASSERTIONS
          next if unknown.empty?

          raise InvalidFixture,
                "step #{step} (#{call}): unknown expect_request keys " \
                "#{unknown.map(&:inspect).join(', ')} (known: " \
                "#{KNOWN_ASSERTIONS.map(&:inspect).join(', ')})"
        end

        fixture[:steps].map { |raw| normalize_step(raw) }
      end

      def assert_fixture(body, step, call, label)
        return if body.nil? || body.is_a?(String) || body.is_a?(Hash) || body.is_a?(Array)

        raise InvalidFixture,
              "step #{step} (#{call}): #{label} must be a String (raw) or " \
              "Hash/Array (JSON), got #{body.class}"
      end

      def normalize_step(raw)
        {
          call: raw[:call].to_sym,
          params: deep_symbolize(raw[:params] || {}),
          response: {
            status: raw[:response].fetch(:status, 200),
            headers: stringify_keys(raw[:response][:headers] || {}),
            body: raw[:response][:body]
          },
          expect_request: raw[:expect_request] &&
            deep_symbolize(raw[:expect_request])
        }
      end

      def deep_symbolize(value)
        case value
        when Hash
          value.each_with_object({}) do |(k, v), h|
            h[k.to_sym] = deep_symbolize(v)
          end
        when Array
          value.map { |v| deep_symbolize(v) }
        else
          value
        end
      end

      def stringify_keys(hash)
        hash.each_with_object({}) { |(k, v), h| h[k.to_s] = v.to_s }
      end

      # --- the player -------------------------------------------------------

      # Drives the client through the validated steps. Hooks registered with
      # {#before_step} / {#after_step} carry the stateful rules that
      # contracts cannot express (token refresh sequencing, rate-limit
      # windows, cross-step invariants).
      class Player
        attr_reader :client, :name, :steps

        def initialize(client, name, steps)
          @client = client
          @name = name
          @steps = steps
          @before_hooks = []
          @after_hooks = []
        end

        # Register a hook run before each step: block.call(step_number, step).
        def before_step(&block)
          @before_hooks << block
          self
        end

        # Register a hook run after each validated step:
        # block.call(step_number, step, response).
        def after_step(&block)
          @after_hooks << block
          self
        end

        # Execute all steps in order. Returns the Array of {Result}. Raises
        # {Failure} on the first violated step; nothing after it runs.
        def run
          webmock!
          results = []
          @steps.each_with_index do |step, index|
            number = index + 1
            results << run_step(number, step)
          end
          results
        end

        private

        def webmock!
          unless defined?(WebMock)
            raise Error,
                  'the sequence helper needs the webmock gem — add it to your ' \
                  "test group and require 'webmock/rspec' (or 'webmock')"
          end

          enabled = false
          WebMock::HttpLibAdapterRegistry.instance.each_adapter do |_name, adapter|
            enabled = true if adapter.respond_to?(:enabled?) && adapter.enabled?
          end
          return if enabled

          raise Error,
                'WebMock is loaded but not enabled — call WebMock.enable! ' \
                "(or require 'webmock/rspec') before running a sequence"
        end

        def run_step(number, step)
          @before_hooks.each { |hook| safe(hook, number, step) { hook.call(number, step) } }

          definition = client.class.contract_for(step[:call])
          register_stub!(definition, step)

          before_counts = signature_counts
          response = begin
            client.public_send(step[:call], **step[:params])
          rescue StandardError => e
            raise Failure.new(number, step[:call], e)
          end

          request = verify_requests!(number, step, definition, before_counts)
          verify_expectations!(number, step, request)

          @after_hooks.each do |hook|
            safe(hook, number, step) { hook.call(number, step, response) }
          end

          Result.new(step: number, call: step[:call], params: step[:params],
                     response: response, request: request)
        end

        # Hooks are stateful user rules; a raise inside one is a step
        # failure, not a crash of the player.
        def safe(_hook, number, step)
          yield
        rescue StandardError => e
          raise Failure.new(number, step[:call], e, "hook failed: #{e.message}")
        end

        # Stub the recorded response. The URL matcher is the base + the path
        # template with placeholders widened to [^/]+ — query-agnostic on
        # purpose (defaults and coercion produce query strings that recorded
        # fixtures did not pin down; use expect_request to pin them).
        def register_stub!(definition, step)
          base = client.__contract_base.to_s
          path = Regexp.escape(definition.path_template)
                       .gsub(/:[a-zA-Z_][a-zA-Z0-9_]*/, '[^/]+')
          pattern = Regexp.escape(base.sub(%r{/+\z}, '')) + path
          response = step[:response]
          headers = response[:headers].dup
          body = response[:body]
          if (body.is_a?(Hash) || body.is_a?(Array)) &&
             !headers.keys.any? { |k| k.to_s.casecmp('content-type').zero? }
            headers['Content-Type'] = 'application/json'
          end
          rendered = body.is_a?(Hash) || body.is_a?(Array) ? JSON.generate(body) : body

          WebMock::API.stub_request(definition.verb, /\A#{pattern}(?:\?.*)?\z/)
                      .to_return(status: response[:status],
                                 headers: headers,
                                 body: rendered || '')
        end

        # Snapshot of issued requests: signature => times. WebMock counts
        # identical signatures, preserving first-occurrence order, which is
        # enough to attribute a request window to a step (retries of the
        # same request collapse into one signature with a higher count).
        def signature_counts
          counts = {}
          WebMock::RequestRegistry.instance.requested_signatures.each do |signature, times|
            counts[signature] = times
          end
          counts
        end

        def verify_requests!(number, step, definition, before_counts)
          after_counts = signature_counts
          new_in_window = after_counts.select do |signature, count|
            count > before_counts.fetch(signature, 0)
          end
          if new_in_window.empty?
            raise Failure.new(number, step[:call], nil,
                              'no HTTP request was made for this step')
          end

          signature = new_in_window.keys.first
          expected_verb = definition.verb
          return signature if signature.method.to_s.downcase == expected_verb.to_s

          raise Failure.new(
            number, step[:call], nil,
            "expected a #{expected_verb.to_s.upcase} request but the client " \
            "issued #{signature.method.to_s.upcase} to #{signature.uri}"
          )
        end

        def verify_expectations!(number, step, signature)
          expected = step[:expect_request]
          return unless expected

          if expected[:path]
            actual = signature.uri.path
            unless actual == expected[:path]
              raise Failure.new(number, step[:call], nil,
                                "expected request path #{expected[:path].inspect}, " \
                                "got #{actual.inspect}")
            end
          end

          if (wanted = expected[:query_include])
            actual = {}
            URI.decode_www_form(signature.uri.query.to_s).each do |key, value|
              (actual[key] ||= []) << value
            end
            missing = subset_violations(wanted, actual)
            unless missing.empty?
              raise Failure.new(number, step[:call], nil,
                                "query params missing or wrong: #{missing.join('; ')} " \
                                "(actual query: #{signature.uri.query.inspect})")
            end
          end

          if (wanted = expected[:headers_include])
            actual = Sequence.stringify_keys(signature.headers || {})
            missing = subset_violations(wanted, actual)
            unless missing.empty?
              raise Failure.new(number, step[:call], nil,
                                "request headers missing or wrong: #{missing.join('; ')}")
            end
          end

          if (wanted = expected[:json_include])
            actual = parse_request_body(number, step, signature)
            missing = deep_subset_violations(wanted, actual)
            unless missing.empty?
              raise Failure.new(number, step[:call], nil,
                                "request payload missing or wrong: #{missing.join('; ')}")
            end
          end
        end

        def subset_violations(wanted, actual)
          wanted.filter_map do |key, value|
            actual_value = actual[key.to_s]
            "expected #{key}=#{value.inspect}" unless actual_value && Array(actual_value).include?(value.to_s)
          end
        end

        def deep_subset_violations(wanted, actual, prefix = nil)
          wanted.filter_map do |key, value|
            dotted = prefix ? "#{prefix}.#{key}" : key.to_s
            if value.is_a?(Hash)
              next "expected #{dotted} inside a JSON object, got #{actual.class}" unless actual.is_a?(Hash)

              nested = actual.key?(key.to_s) ? actual[key.to_s] : actual[key]
              deep_subset_violations(value, nested, dotted)
            elsif actual.is_a?(Hash) && (actual.key?(key.to_s) || actual.key?(key))
              found = actual.key?(key.to_s) ? actual[key.to_s] : actual[key]
              next unless found != value

              "expected #{dotted}=#{value.inspect}, got #{found.inspect}"
            else
              "expected #{dotted} in the request payload"
            end
          end.flatten
        end

        def parse_request_body(number, step, signature)
          raw = signature.body.to_s
          JSON.parse(raw)
        rescue JSON::ParserError
          raise Failure.new(number, step[:call], nil,
                            'json_include assertion requires a JSON request ' \
                            "payload, got #{raw.empty? ? 'an empty body' : raw[0, 60].inspect}")
        end
      end
    end
  end
end
