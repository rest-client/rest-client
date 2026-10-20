# frozen_string_literal: true

module Contractful
  module Contract
    # Authentication schemes declared on a contract-first client.
    #
    # The contract is the source of truth for HOW to authenticate; the
    # client supplies only the credentials. Values may be literals or
    # callables — callables are invoked on every request so short-lived
    # tokens stay fresh:
    #
    #   auth bearer: -> { fetch_token }                       # Authorization: Bearer ...
    #   auth api_key: { name: 'access-token', value: token }  # custom header
    #   auth api_key: [                                       # multiple keys at once
    #     { name: 'access-token', value: -> { token } },
    #     { name: 'client-id',    value: client_id },
    #   ]
    #   auth basic: -> { [user, pass] }                       # Authorization: Basic ...
    #
    # api_key schemes can also live in the query string with
    # <tt>in: :query</tt>.
    #
    # Auth is resolved right before the before_request callbacks run, so
    # callbacks can still inspect or override the resolved credentials.
    class Auth # rubocop:disable Metrics/ClassLength
      VALID_LOCATIONS = %i[header query].freeze

      attr_reader :schemes

      def initialize(**schemes)
        if schemes.empty?
          raise InvalidDefinition,
                'auth requires at least one scheme (bearer:, api_key:, basic: or token_provider:)'
        end

        @schemes = []
        schemes.each do |name, value|
          case name
          when :bearer then add_bearer(value)
          when :api_key then add_api_keys(value)
          when :basic then add_basic(value)
          when :token_provider then add_token_provider(value)
          else
            raise InvalidDefinition,
                  "unknown auth scheme #{name.inspect} " \
                  '(supported: :bearer, :api_key, :basic, :token_provider)'
          end
        end
        freeze_scheme_values!
      end

      # Resolve the schemes against the current moment: callable values are
      # invoked now, so tokens fetched per request are always fresh.
      #
      # @return [Hash] +{ headers: Hash, query: Hash }+ to merge into the
      #   outgoing request
      def resolve
        headers = {}
        query = {}
        @schemes.each do |scheme|
          case scheme[:scheme]
          when :token_provider
            headers['Authorization'] = "Bearer #{scheme[:value].token}"
          when :bearer
            headers['Authorization'] = "Bearer #{credential(scheme[:value])}"
          when :basic
            user, pass = credential(scheme[:value])
            token = ["#{user}:#{pass}"].pack('m0')
            headers['Authorization'] = "Basic #{token}"
          when :api_key
            value = credential(scheme[:value])
            if scheme[:location] == :query
              query[scheme[:name].to_s] = value
            else
              headers[scheme[:name].to_s] = value
            end
          end
        end
        { headers: headers, query: query }
      end

      # The token provider object when the contract authenticates with
      # <tt>auth token_provider:</tt>, otherwise nil. The executor uses this
      # to drive the refresh-on-401 flow.
      def token_provider
        scheme = @schemes.find { |s| s[:scheme] == :token_provider }
        scheme && scheme[:value]
      end

      def to_s
        @schemes.map { |s| s[:scheme] }.uniq.join('+')
      end

      def inspect
        "#<Contractful::Contract::Auth #{self}>"
      end

      private

      def add_bearer(value)
        validate_credential!(value, :bearer)
        @schemes << { scheme: :bearer, value: value }
      end

      # A token provider is an object, not a callable: it must answer
      # #token (the current credential) and #refresh (force a new token).
      # The executor refreshes it in one flight when a 401 arrives.
      def add_token_provider(value)
        unless value.respond_to?(:token) && value.respond_to?(:refresh)
          raise InvalidDefinition,
                'auth token_provider: expects an object responding to ' \
                '#token and #refresh, got ' + value.inspect
        end
        @schemes << { scheme: :token_provider, value: value }
      end

      def add_api_keys(value)
        # Array() would explode a Hash into key/value pairs — normalize here.
        entries = value.is_a?(Array) ? value : [value]
        entries.each do |entry|
          unless entry.is_a?(Hash)
            raise InvalidDefinition,
                  'auth api_key: expects a Hash {name:, value:, in:} or an ' \
                  "Array of them, got #{entry.inspect}"
          end
          name = entry[:name] || entry['name']
          unless name.is_a?(String) || name.is_a?(Symbol)
            raise InvalidDefinition,
                  "auth api_key: requires a name, got #{name.inspect}"
          end
          credential_value = entry[:value] || entry['value']
          validate_credential!(credential_value, :api_key)
          location = (entry[:in] || entry['in'] || :header).to_sym
          unless VALID_LOCATIONS.include?(location)
            raise InvalidDefinition,
                  "auth api_key: in: must be :header or :query, got #{location.inspect}"
          end
          @schemes << { scheme: :api_key, name: name,
                        value: credential_value, location: location }
        end
      end

      def add_basic(value)
        validate_credential!(value, :basic)
        @schemes << { scheme: :basic, value: value }
      end

      def validate_credential!(value, scheme_name)
        ok = value.is_a?(String) || value.is_a?(Symbol) ||
             (value.is_a?(Array) && scheme_name == :basic) ||
             value.respond_to?(:call)
        return if ok

        raise InvalidDefinition,
              "auth #{scheme_name}: value must be a literal or a callable, " \
              "got #{value.inspect}"
        
      end

      def credential(value)
        value.respond_to?(:call) ? value.call : value
      end

      # Basic-auth pairs are resolved lazily; everything else is frozen so a
      # misconfigured literal fails fast.
      def freeze_scheme_values!
        @schemes.each do |scheme|
          scheme[:value].freeze if scheme[:scheme] != :basic && scheme[:value].is_a?(String)
        end
        @schemes.freeze
      end
    end

    # One-flight refresh coordination for token providers: concurrent 401s
    # for the same provider never run #refresh concurrently — the first
    # caller holds the per-provider mutex while refreshing, later callers
    # block and then proceed with the fresh token (their #token call sees
    # the new credential). Refreshes post a `token_refresh` notification.
    module TokenRefresh
      @registry = {}
      @mutex = Mutex.new

      class << self
        def refresh(provider)
          lock_for(provider).synchronize do
            token = provider.refresh
            Notifications.post('token_refresh',
                               provider: provider.class.name)
            token
          end
        end

        def clear!
          @mutex.synchronize { @registry.clear }
        end

        private

        def lock_for(provider)
          @mutex.synchronize { @registry[provider] ||= Mutex.new }
        end
      end
    end
  end
end
