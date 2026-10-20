# frozen_string_literal: true

# Contract layer: declarative, first-class API definitions compiled into
# real methods (see docs/adr/0002 and 0003).
module Contractful
  # Declaration DSL and metaprogramming machinery for contract clients.
  module Contract
    # Metaprogramming machinery injected into classes that include
    # {Contractful::Contract}.
    #
    # {ClassMethods} provides the declaration macros (+base+, +contract+, ...)
    # and generates one real instance method per contract via +define_method+
    # (plus a <tt>#{name}_url</tt> path builder). {InstanceMethods} provides
    # the small runtime surface the {Executor} needs.
    module ClassMethods
      # Configure the base URL all contract paths are resolved against.
      # Trailing slashes are stripped.
      def base(url)
        unless url.is_a?(String) && url.match?(%r{\Ahttps?://}i)
          raise InvalidDefinition,
                "base must be an absolute http(s) URL, got #{url.inspect}"
        end
        __own_contract_config.base_url = url.sub(%r{/+\z}, '')
      end

      # Declare default headers merged into every request. Called with no
      # arguments it returns the headers accumulated down the ancestor chain.
      def default_headers(headers = nil)
        if headers.nil?
          merged = {}
          __contract_config_chain.reverse_each do |config|
            merged.update(config.default_headers) if config.default_headers
          end
          merged
        else
          __own_contract_config.default_headers = headers
        end
      end

      # Toggle strict param checking (default: strict). In strict mode,
      # providing params the contract does not declare raises {UnknownParam}.
      def strict_params(flag = true)
        __own_contract_config.strict_params = flag
      end

      # Default payload style for non-query params: +:json+ or +:form+.
      # Per-contract `payload_style` inside the block wins over this.
      def payload_style(style)
        __own_contract_config.payload_style = style
      end

      # Declare the authentication scheme(s) for this client. The contract is
      # the source of truth for HOW to authenticate; you supply only the
      # credentials (literals or callables — callables are invoked per
      # request so tokens stay fresh):
      #
      #   auth bearer: -> { ENV['API_TOKEN'] }
      #   auth api_key: { name: 'access-token', value: -> { token } }
      #   auth api_key: [
      #     { name: 'access-token', value: -> { token } },
      #     { name: 'client-id',    value: client_id },
      #   ]
      #   auth basic: -> { [user, pass] }
      #
      # Called with no arguments it returns the resolved Auth object (or
      # nil/false). Individual contracts can opt out with
      # <tt>auth false</tt> inside the contract block.

      def auth(**schemes)
        return __merged_scalar(:auth) if schemes.empty?

        __own_contract_config.auth = Contract::Auth.new(**schemes)
      end

      # Header carrying the idempotency key (default 'Idempotency-Key').
      def idempotency_header(name = nil)
        return __merged_scalar(:idempotency_header) || 'Idempotency-Key' if name.nil?

        __own_contract_config.idempotency_header = name
      end

      # Generator producing idempotency keys (default: SecureRandom.uuid).
      def idempotency_generator(generator = nil)
        if generator.nil?
          return __merged_scalar(:idempotency_generator) ||
                 -> { ::SecureRandom.uuid }
        end
        __own_contract_config.idempotency_generator = generator
      end

      # Register a callback executed before the HTTP request is sent. The
      # block receives a mutable context Hash:
      #
      #   { definition:, method:, url:, headers:, payload:, query: }
      #
      # Mutating the context changes the outgoing request (for example
      # injecting Authorization headers or rewriting the URL). Callbacks
      # accumulate down the inheritance chain, root-most first.
      def before_request(&block)
        __own_contract_config.add_callback(:before_request, block)
      end

      # Register a callback executed after a contract-valid response is
      # received (after response validation, before the contract method
      # returns). The block receives the Contractful::Response; return values
      # are ignored. Callbacks accumulate down the inheritance chain,
      # root-most first.
      def after_response(&block)
        __own_contract_config.add_callback(:after_response, block)
      end

      # Generate the five standard REST contracts for a collection. The
      # contracts are registered and method-generated exactly like hand
      # written ones — they show up in introspection and get `*_url`
      # builders for free:
      #
      #   resource :posts
      #
      # is equivalent to declaring:
      #
      #   contract :list_posts,   'GET /posts'
      #   contract :get_post,     'GET /posts/:id'
      #   contract :create_post,  'POST /posts'
      #   contract :update_post,  'PATCH /posts/:id'
      #   contract :delete_post,  'DELETE /posts/:id'
      #
      # Generated CRUD contracts are non-strict: undeclared params flow
      # through to the query string / payload, since CRUD endpoints take
      # free-form attributes. Declare contracts by hand instead when you want
      # strict validation for a specific operation.
      #
      # @param plural [Symbol] collection name (also the default path segment)
      # @param path [String] override the collection path (default "/#{plural}")
      # @param only [Array<Symbol>] restrict to a subset of
      #   %i[index show create update destroy]
      # @param except [Array<Symbol>] exclude some of the actions
      # @param update_with [Symbol] verb for the update action (:patch or :put)
      # @param singular [Symbol] override the auto-singularized member name
      #
      # @return [Hash] action name => generated contract name
      def resource(plural, path: nil, only: nil, except: nil,
                   update_with: :patch, singular: nil)
        plural = plural.to_sym
        unless plural.to_s.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
          raise InvalidDefinition,
                "resource name #{plural.inspect} is not a valid identifier"
        end
        unless %i[patch put].include?(update_with.to_sym)
          raise InvalidDefinition,
                "update_with must be :patch or :put, got #{update_with.inspect}"
        end
        raise InvalidDefinition, 'resource accepts :only or :except, not both' if only && except

        member = (singular || __singularize(plural)).to_sym
        collection_path = path || "/#{plural}"
        unless collection_path.start_with?('/')
          raise InvalidDefinition,
                "resource path #{collection_path.inspect} must start with \"/\""
        end
        member_path = "#{collection_path.sub(%r{/+\z}, '')}/:id"

        actions = {
          index: ["GET #{collection_path}", :"list_#{plural}"],
          show: ["GET #{member_path}", :"get_#{member}"],
          create: ["POST #{collection_path}", :"create_#{member}"],
          update: ["#{update_with.to_s.upcase} #{member_path}", :"update_#{member}"],
          destroy: ["DELETE #{member_path}", :"delete_#{member}"]
        }
        actions = __filter_resource_actions(actions, only, except)

        actions.each_value do |request_line, name|
          contract(name, request_line) { strict_params false }
        end
        actions.transform_values(&:last)
      end

      # Declare a contract. The request line is <tt>'VERB /path'</tt>; the
      # optional block is instance_eval'd against the new {Definition}.
      #
      # @return [Definition] the registered definition
      def contract(name, request_line, description: nil, &block)
        name = name.to_sym
        validate_contract_name!(name)

        verb, path = parse_request_line(request_line)
        definition = Definition.new(name, verb, path, description: description, &block)

        __own_contract_config.contracts[name] = definition
        __define_contract_methods(definition)
        definition
      end

      # --- reflection / introspection ------------------------------------------

      # All contracts visible from this class, merged down the ancestor chain
      # (nearest definition wins). Returns a defensive copy.
      def contracts
        __merged_contracts.dup
      end

      # Names of all contracts visible from this class.
      def contract_names
        __merged_contracts.keys
      end

      # Does this class (or an ancestor) declare a contract named +name+?
      def contract?(name)
        __merged_contracts.key?(name.to_sym)
      end

      # The {Definition} for +name+, or nil when unknown.
      def contract_for(name)
        __merged_contracts[name.to_sym]
      end

      # --- machinery (used by Executor / introspection) -----------------------

      # The config object owned by *this* class (created on demand).
      def __own_contract_config
        @__contract_config ||= Config.new
      end

      # Config objects along the ancestor chain, self first.
      def __contract_config_chain
        chain = []
        klass = self
        while klass.is_a?(Class)
          if klass.instance_variable_defined?(:@__contract_config)
            chain << klass.instance_variable_get(:@__contract_config)
          end
          klass = klass.superclass
        end
        chain
      end

      # Nearest non-nil scalar setting down the chain (base_url,
      # strict_params, payload_style).
      def __merged_scalar(setting)
        __contract_config_chain.each do |config|
          value = config.public_send(setting)
          return value unless value.nil?
        end
        nil
      end

      # Contracts merged down the ancestor chain, root-most first (nearest
      # definition wins on name collisions).
      def __merged_contracts
        merged = {}
        __contract_config_chain.reverse_each do |config|
          merged.update(config.contracts)
        end
        merged
      end

      # Callbacks of one kind, accumulated root-first.
      def __merged_callbacks(kind)
        __contract_config_chain.reverse_each.flat_map { |c| c.callbacks[kind] }
      end

      private

      def parse_request_line(line)
        match = line.to_s.match(
          %r{\A\s*(GET|HEAD|POST|PUT|PATCH|DELETE|OPTIONS)\s+(/\S*)\s*\z}i
        )
        unless match
          raise InvalidDefinition,
                "invalid request line #{line.inspect} — expected " \
                "'VERB /path', e.g. 'GET /users' or 'POST /repos/:owner/:repo/issues'"
        end
        [match[1].downcase.to_sym, match[2]]
      end

      def validate_contract_name!(name)
        unless name.to_s.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*[?!]?\z/)
          raise InvalidDefinition,
                "contract name #{name.inspect} is not a valid method name"
        end
        return unless RESERVED_NAMES.include?(name)

        raise InvalidDefinition,
              "contract name #{name.inspect} is reserved and cannot be used"
        
      end

      # Filter resource actions according to :only / :except (already
      # validated: they are never both present).
      def __filter_resource_actions(actions, only, except)
        if only
          wanted = Array(only).map(&:to_sym)
          unknown = wanted - actions.keys
          unless unknown.empty?
            raise InvalidDefinition,
                  "unknown resource actions #{unknown.map(&:inspect).join(', ')} " \
                  "(known: #{actions.keys.map(&:inspect).join(', ')})"
          end
          actions.select { |action, _| wanted.include?(action) }
        elsif except
          unwanted = Array(except).map(&:to_sym)
          unknown = unwanted - actions.keys
          unless unknown.empty?
            raise InvalidDefinition,
                  "unknown resource actions #{unknown.map(&:inspect).join(', ')} " \
                  "(known: #{actions.keys.map(&:inspect).join(', ')})"
          end
          actions.reject { |action, _| unwanted.include?(action) }
        else
          actions
        end
      end

      IRREGULAR_SINGULARS = {
        people: 'person', children: 'child', men: 'man', women: 'woman',
        teeth: 'tooth', feet: 'foot', mice: 'mouse', geese: 'goose'
      }.freeze

      # Deliberately small singularization for the `resource` macro: covers
      # regular English plurals and the most common irregulars. Override with
      # the `singular:` option when the guess is wrong.
      def __singularize(word)
        w = word.to_s
        return IRREGULAR_SINGULARS[w.to_sym] if IRREGULAR_SINGULARS.key?(w.to_sym)

        if w.match?(/ies\z/)
          w.sub(/ies\z/, 'y')
        elsif w.match?(/(ss|x|z|ch|sh)es\z/) || w.match?(/ses\z/)
          # both branches strip a trailing 'es' (order-preserving merge of
          # previously duplicated branches)
          w.sub(/es\z/, '')
        elsif w.match?(/[^s]s\z/)
          w.sub(/s\z/, '')
        else
          w
        end
      end

      # Generate the client methods for a contract:
      #
      #   name        -> execute the contract
      #   name_url    -> expand path params and return the full URL
      def __define_contract_methods(definition)
        name = definition.name

        define_method(name) do |**params|
          Contract::Executor.call(self, definition, params)
        end

        define_method(:"#{name}_url") do |**params|
          Contract::Executor.build_url(self, definition, params)
        end

        return unless definition.pagination

        # Metaprogrammed pagination: every paginated contract gets an
        # enumerator of validated pages plus a flat collector, driven by the
        # contract's own pagination declaration.
        define_method(:"#{name}_pages") do |**params|
          Contract::Pagination.each_page(self, definition, params)
        end

        define_method(:"all_#{name}") do |**params|
          Contract::Pagination.all_items(self, definition, params)
        end
      end
    end

    # Instance methods mixed into contract client classes: convenience
    # dispatch (`call_*`, `*_contract`, `has_*?`) on top of the generated
    # methods.
    module InstanceMethods
      # Client-level overrides. They take precedence over the class-level
      # configuration; if the class defines its own #initialize it wins (call
      # <tt>super(base:, headers:)</tt> to keep both).
      def initialize(base: nil, headers: nil)
        @__base_override = base
        @__header_overrides = headers || {}
      end

      # --- reflection / introspection ----------------------------------------

      # @see ClassMethods#contracts
      def contracts
        self.class.contracts
      end

      # @see ClassMethods#contract_names
      def contract_names
        self.class.contract_names
      end

      # @see ClassMethods#contract?
      def contract?(name)
        self.class.contract?(name)
      end

      # @see ClassMethods#contract_for
      def contract_for(name)
        self.class.contract_for(name)
      end

      # Dynamic dispatch for contract conveniences. Real methods (including
      # generated contract methods) always take precedence, so a contract
      # literally named +call_ping+ is unaffected by the +call_*+ pattern.
      #
      #   client.call_list_posts(**params)  # alias of client.list_posts
      #   client.list_posts_contract        # => the Definition
      #   client.has_list_posts?            # => contract presence predicate
      #                                       (false when unknown, never raises)
      def method_missing(name, *args, **kwargs, &block)
        string = name.to_s

        if (match = string.match(/\Acall_(.+)\z/)) &&
           (definition = self.class.contract_for(match[1]))
          return Contract::Executor.call(self, definition, kwargs)
        end

        if (match = string.match(/\A(.+)_contract\z/)) &&
           (definition = self.class.contract_for(match[1]))
          return definition
        end

        if (match = string.match(/\Ahas_(.+)\?\z/))
          # Predicate semantics: unknown contracts are simply absent.
          return self.class.contract?(match[1])
        end

        super
      end

      def respond_to_missing?(name, include_private = false)
        string = name.to_s

        if (match = string.match(/\Acall_(.+)\z/)) && self.class.contract?(match[1])
          return true
        end
        if (match = string.match(/\A(.+)_contract\z/)) && self.class.contract?(match[1])
          return true
        end
        return true if string.match?(/\Ahas_.+\?\z/)

        super
      end

      # Base URL for this instance (constructor override > class config).
      def __contract_base
        @__base_override || self.class.__merged_scalar(:base_url) ||
          raise(MissingBaseUrl,
                'no base URL configured — use `base "https://api.example.com"` ' \
                'or pass base: to the constructor')
      end

      # Merge class default headers (root-first), instance header overrides
      # and per-call _headers into one effective Hash.
      def __contract_effective_headers(call_headers)
        merged = self.class.default_headers
        merged.update(@__header_overrides) if @__header_overrides
        merged.update(call_headers) if call_headers
        merged
      end

      # Run the accumulated before_request callbacks with the mutable
      # execution context (root-most callbacks first).
      def __run_before_callbacks(ctx)
        self.class.__merged_callbacks(:before_request).each { |cb| cb.call(ctx) }
      end

      # Run the accumulated after_response callbacks with the response.
      def __run_after_callbacks(response)
        self.class.__merged_callbacks(:after_response).each { |cb| cb.call(response) }
      end
    end

    RESERVED_NAMES = %i[
      initialize inspect to_s class object_id method_missing respond_to_missing?
      == equal? hash freeze frozen? dup clone send public_send
    ].freeze

    class << self
      # Called when the DSL module is included in a client class: extend the
      # class with the declaration macros and include the runtime methods.
      def included(base)
        base.extend(ClassMethods)
        base.include(InstanceMethods)
      end
    end
  end
end
