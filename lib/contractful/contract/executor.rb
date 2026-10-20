# frozen_string_literal: true

require 'json'

module Contractful
  module Contract
    # Turns a {Definition} plus user-supplied params into a real HTTP request,
    # executes it through the normal contractful machinery and returns the
    # {Contractful::Response}.
    #
    # The pipeline is:
    #
    #   1. symbolize keys, split per-call meta options (+_headers+, ...)
    #   2. validate & coerce params against the contract
    #   3. expand the path template, route remaining params to query/payload
    #   4. run before_request callbacks with a mutable context
    #   5. execute via Contractful::Request
    #   6. run after_response callbacks
    module Executor
      # Per-call meta options (underscore prefix keeps them out of the
      # contract's param namespace).
      META_OPTIONS = %i[
        _headers _timeout _open_timeout _read_timeout _write_timeout
        _persistent _max_retries _retry_interval _idempotency_key
        _retry_jitter _retry_jitter_cap _retry_rng _breaker _pace
      ].freeze

      META_MAP = {
        _timeout: :timeout,
        _open_timeout: :open_timeout,
        _read_timeout: :read_timeout,
        _write_timeout: :write_timeout,
        _persistent: :persistent,
        _max_retries: :max_retries,
        _retry_interval: :retry_interval,
        _retry_jitter: :retry_jitter,
        _retry_jitter_cap: :retry_jitter_cap,
        _retry_rng: :retry_rng,
        _breaker: :breaker,
        _pace: :pace
      }.freeze

      # Verbs whose params are sent as a query string by default.
      QUERY_VERBS = %i[get head delete options].freeze

      module_function

      # Execute a contract.
      #
      # @param instance a client instance (includes Contractful::Contract)
      # @param definition [Definition]
      # @param params [Hash] user-supplied params (String or Symbol keys)
      # @return [Contractful::Response]
      def call(instance, definition, params)
        params = symbolize_keys(params)
        meta, params = split_meta(params)
        coerced = validate_params(instance, definition, params)
        path, remaining = definition.expand_path(coerced)
        url = build_full_url(instance.__contract_base, path)

        verb = definition.verb
        headers = instance.__contract_effective_headers(meta[:_headers])
        payload, query, headers =
          build_body_and_query(instance, definition, verb, remaining, headers)

        ctx = {
          definition: definition,
          method: verb,
          url: url,
          headers: headers,
          payload: payload,
          query: query
        }

        apply_auth!(ctx, instance, definition)
        apply_idempotency!(ctx, instance, definition, meta)

        response = transmit(ctx, instance, definition, meta)

        # OAuth-style refresh-on-401: one-flight refresh of the contract's
        # token provider, then exactly one retry with the fresh credential.
        provider = token_provider_for(instance, definition)
        if response.code.to_i == 401 && provider && !ctx.key?(:__token_refreshed)
          TokenRefresh.refresh(provider)
          ctx[:__token_refreshed] = true
          apply_auth!(ctx, instance, definition)
          response = transmit(ctx, instance, definition, meta)
        end

        validate_response!(definition, response)
        instance.__run_after_callbacks(response)
        response
      end

      # Build the full URL for a contract (used by the generated
      # <tt>#{name}_url</tt> methods). Only path params are required; other
      # declared params are accepted but not appended.
      def build_url(instance, definition, params)
        params = symbolize_keys(params || {})
        coerced = {}
        definition.path_param_names.each do |key|
          param = definition.params[key]
          value = params.key?(key) && !params[key].nil? ? params[key] : nil
          value = param.default_value if value.nil? && param&.has_default?
          if value.nil?
            raise MissingParam,
                  "path param :#{key} is required by " \
                  "#{definition.path_template.inspect} but was not provided"
          end
          coerced[key] = param ? param.process!(value) : value
        end
        path, = definition.expand_path(coerced)
        build_full_url(instance.__contract_base, path)
      end

      # --- internals ---------------------------------------------------------

      # Run the before-callbacks and send the request. Extracted so the
      # refresh-on-401 flow can re-run the identical phase with fresh auth.
      def transmit(ctx, instance, definition, meta)
        instance.__run_before_callbacks(ctx)

        request_args = {
          method: ctx[:method],
          url: ctx[:url],
          headers: ctx[:headers],
          payload: ctx[:payload]
        }
        request_args[:headers] = request_args[:headers].merge(params: ctx[:query]) if ctx[:query] && !ctx[:query].empty?
        merge_meta_options!(request_args, meta)

        execute_request(request_args, definition, instance)
      end

      def token_provider_for(instance, definition)
        return nil if definition.auth.equal?(false)

        # auth may be declared on the contract itself or on the class
        [definition.auth, instance.class.__merged_scalar(:auth)].each do |auth|
          next unless auth.is_a?(Contractful::Contract::Auth)

          provider = auth.token_provider
          return provider if provider
        end
        nil
      end

      # Execute the request. When the contract declares expected error
      # statuses (4xx/5xx) or a token provider can recover from a 401, the
      # default contractful exception behavior is suppressed and every
      # response is judged by the contract instead.
      def execute_request(request_args, definition, instance)
        if declares_error_status?(definition) || token_provider_for(instance, definition)
          Contractful::Request.execute(request_args) do |response|
            handle_suppressed(response)
          end
        else
          Contractful::Request.execute(request_args)
        end
      end

      # Does the contract declare any 4xx/5xx status (directly or via range)?
      def declares_error_status?(definition)
        return false unless definition.response_statuses

        definition.response_statuses.any? do |status|
          if status.is_a?(Range)
            status.min <= 599 && status.max >= 400
          else
            status >= 400
          end
        end
      end

      # Mirror AbstractResponse#return! for redirects while suppressing the
      # final error-raising: redirectable 30x responses are still followed
      # (recursively), everything else is returned for contract validation.
      def handle_suppressed(response)
        case response.code
        when 301, 302, 307
          if %w[get head].include?(response.request.method)
            response.follow_redirection { |redirected| handle_suppressed(redirected) }
          else
            response
          end
        when 303
          response.follow_get_redirection { |redirected| handle_suppressed(redirected) }
        else
          response
        end
      end

      # Validate the response against the contract's response declaration:
      # declared statuses, JSON body type and verify_response blocks.
      def validate_response!(definition, response)
        return response unless needs_validation?(definition)

        status = response.code
        if definition.response_statuses &&
           !definition.response_statuses.any? { |s| s === status }
          raise UnexpectedResponse.new(
            "unexpected status #{status} for #{definition.describe} " \
            "(expected #{render_statuses(definition.response_statuses)})",
            response: response
          )
        end

        parsed = nil
        if definition.response_type
          parsed = parse_response_body(response, definition)
          unless response_type_matches?(definition.response_type, parsed)
            raise UnexpectedResponse.new(
              "response body does not match #{definition.response_type_name} " \
              "for #{definition.describe}",
              response: response
            )
          end
        end

        unless definition.response_fields.empty?
          parsed = parse_json_object(response, definition)
          violations = definition.response_fields.flat_map do |_, field|
            field.violations_for(parsed)
          end
          unless violations.empty?
            raise UnexpectedResponse.new(
              "response violates contract for #{definition.describe}: " \
              "#{violations.join('; ')}",
              response: response
            )
          end
        end

        if definition.response_verifier &&
           !call_verifier(definition.response_verifier, response, parsed)
          raise UnexpectedResponse.new(
            "verify_response block rejected the response for #{definition.describe}",
            response: response
          )
        end

        response
      end

      def needs_validation?(definition)
        definition.response_statuses || definition.response_type ||
          definition.response_verifier || !definition.response_fields.empty?
      end

      def render_statuses(statuses)
        statuses.map { |s| s.is_a?(Range) ? s.inspect : s.to_s }.join(', ')
      end

      def parse_response_body(response, definition)
        return response.body if definition.response_type.equal?(String)

        body = response.body
        if body.nil? || body.empty?
          raise UnexpectedResponse.new(
            "expected #{definition.response_type_name} but the response body " \
            "is empty for #{definition.describe}",
            response: response
          )
        end

        begin
          JSON.parse(body)
        rescue JSON::ParserError => e
          raise UnexpectedResponse.new(
            "response body is not valid JSON for #{definition.describe}: #{e.message}",
            response: response
          )
        end
      end

      # Parse the response body as a JSON object for response_field checks.
      def parse_json_object(response, definition)
        body = response.body
        if body.nil? || body.empty?
          raise UnexpectedResponse.new(
            'expected a JSON object but the response body is empty ' \
            "for #{definition.describe}",
            response: response
          )
        end

        parsed = begin
          JSON.parse(body)
        rescue JSON::ParserError => e
          raise UnexpectedResponse.new(
            "response body is not valid JSON for #{definition.describe}: #{e.message}",
            response: response
          )
        end
        unless parsed.is_a?(Hash)
          raise UnexpectedResponse.new(
            "expected a JSON object but got #{parsed.class} " \
            "for #{definition.describe} " \
            '(response fields require an object body)',
            response: response
          )
        end
        parsed
      end

      def response_type_matches?(type, parsed)
        return true if type.equal?(:json)
        return true if type.equal?(String)

        parsed.is_a?(type)
      end

      # Arity-aware verifier invocation: blocks that declare two parameters
      # additionally receive the JSON-parsed body (parsed lazily).
      def call_verifier(block, response, parsed)
        if block.arity >= 2
          parsed ||= begin
            JSON.parse(response.body)
          rescue StandardError
            nil
          end
          block.call(response, parsed)
        else
          block.call(response)
        end
      end

      # Resolve the contract's auth scheme (unless the contract opted out
      # with `auth false`) and merge its headers/query into the context.
      # Auth runs before the before_request callbacks, so callbacks can
      # still inspect or override the resolved credentials.
      def apply_auth!(ctx, instance, definition)
        return if definition.auth.equal?(false)

        auth = instance.class.__merged_scalar(:auth)
        return unless auth.is_a?(Auth)

        resolved = auth.resolve
        ctx[:headers] = ctx[:headers].merge(resolved[:headers]) unless resolved[:headers].empty?
        return if resolved[:query].empty?

        ctx[:query] = (ctx[:query] || {}).merge(resolved[:query])
        
      end

      # Inject an idempotency key when the contract is flagged `idempotent`
      # or the caller supplied an explicit `_idempotency_key`. The key is
      # generated once per logical call, so automatic retries of the same
      # request reuse it (that is the entire point of the header).
      def apply_idempotency!(ctx, instance, definition, meta)
        explicit = meta[:_idempotency_key]
        return unless explicit || definition.idempotent.equal?(true)

        key = explicit || instance.class.idempotency_generator.call
        header = instance.class.idempotency_header
        ctx[:headers] = ctx[:headers].merge(header => key)
      end

      def symbolize_keys(hash)
        hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
      end

      def split_meta(params)
        meta = {}
        regular = {}
        params.each do |key, value|
          if key.to_s.start_with?('_')
            unless META_OPTIONS.include?(key)
              raise UnknownParam,
                    "unknown meta option #{key.inspect} " \
                    "(supported: #{META_OPTIONS.map(&:inspect).join(', ')})"
            end
            raise ParamError, "_headers must be a Hash, got #{value.inspect}" if key == :_headers && !value.is_a?(Hash)

            meta[key] = value
          else
            regular[key] = value
          end
        end
        [meta, regular]
      end

      def validate_params(instance, definition, params)
        coerced = {}
        definition.params.each do |name, param|
          value = params[name]
          if !value.nil?
            coerced[name] = param.process!(value)
          elsif param.has_default?
            coerced[name] = param.process!(param.default_value)
          elsif param.required?
            raise MissingParam,
                  "param :#{name} is required by #{definition.describe}"
          end
        end

        unknown = params.keys - definition.params.keys
        if unknown.any?
          if strict_params?(instance, definition)
            raise UnknownParam,
                  "unknown param #{unknown.map { |k| ":#{k}" }.join(', ')} " \
                  "for #{definition.describe} " \
                  '(disable with strict_params false)'
          end
          unknown.each { |key| coerced[key] = params[key] }
        end
        coerced
      end

      def strict_params?(instance, definition = nil)
        # Per-contract override wins over the class-level setting.
        return definition.strict if definition && !definition.strict.nil?

        value = instance.class.__merged_scalar(:strict_params)
        value.nil? || value
      end

      def effective_payload_style(instance, definition, verb)
        definition.payload_style ||
          instance.class.__merged_scalar(:payload_style) ||
          (QUERY_VERBS.include?(verb) ? :query : :json)
      end

      def build_body_and_query(instance, definition, verb, remaining, headers)
        return [nil, nil, headers] if remaining.empty?

        style = effective_payload_style(instance, definition, verb)
        if QUERY_VERBS.include?(verb) || style == :query
          [nil, remaining, headers]
        elsif style == :form
          [remaining, nil, headers]
        else # :json
          unless headers.keys.any? { |k| k.to_s.casecmp('content-type').zero? }
            headers = headers.merge('Content-Type' => 'application/json')
          end
          [JSON.generate(remaining), nil, headers]
        end
      end

      def build_full_url(base, path)
        base = base.sub(%r{/+\z}, '')
        path = "/#{path}" unless path.start_with?('/')
        "#{base}#{path}"
      end

      def merge_meta_options!(request_args, meta)
        META_MAP.each do |meta_key, option_key|
          request_args[option_key] = meta[meta_key] if meta.key?(meta_key)
        end
      end
    end
  end
end
