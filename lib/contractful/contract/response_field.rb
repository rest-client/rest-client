# frozen_string_literal: true

module Contractful
  module Contract
    # A single declared field of a response payload — the "open" side of a
    # contract.
    #
    # Response schemas are deliberately OPEN, unlike request params:
    #
    #   * +required+ and +type+ BIND: a declared required field that is
    #     missing (or null), or a field whose value does not match the
    #     declared type, raises {UnexpectedResponse} when the response is
    #     received.
    #   * Everything else is ADDITIVE DATA: fields that were never declared
    #     are passed through untouched, and declared +inclusion+ sets are
    #     NOT enforced unless <tt>strict: true</tt> is given — a new enum
    #     member the client does not know about yet is data, not an error.
    #   * Values are never coerced: what the server sent is what you get.
    #
    # Example:
    #
    #   contract :create_order, 'POST /orders' do
    #     response_field :order_id, :string, required: true
    #     response_field :status, :string   # open: new states are additive
    #   end
    class ResponseField
      # Symbol aliases accepted for +type+. +:boolean+ matches true/false,
      # +:number+ matches any Numeric (Integer or Float).
      SYMBOL_TYPES = {
        string: String,
        integer: Integer,
        float: Float,
        array: Array,
        hash: Hash,
        number: :number,
        boolean: :boolean
      }.freeze

      attr_reader :name, :type, :inclusion, :description

      def initialize(name, type = nil, required: false, inclusion: nil,
                     strict: false, description: nil)
        @name = name.to_sym
        @type = normalize_type(type)
        @required = required ? true : false
        @inclusion = inclusion
        @strict = strict ? true : false
        @description = description
        validate_definition!
      end

      def required?
        @required
      end

      def strict?
        @strict
      end

      # Check a parsed JSON object against this field.
      #
      # JSON.parse yields String-keyed hashes, so both Symbol and String key
      # spellings are looked up (Symbol first — internal hashes tend to be
      # symbol-keyed).
      #
      # @return [Array<String>] every violation message (empty when the
      #   payload conforms)
      def violations_for(payload)
        if payload.key?(@name)
          value = payload[@name]
        elsif payload.key?(string_name = @name.to_s)
          value = payload[string_name]
        else
          return @required ? ["field :#{@name} is required but missing"] : []
        end

        msgs = []
        if value.nil?
          msgs << "field :#{@name} is required but was null" if @required
        else
          msgs.concat(type_violations(value))
          msgs.concat(inclusion_violations(value))
        end
        msgs
      end

      # Human-readable summary used in error messages and introspection.
      def to_s
        parts = [type_name]
        parts << 'required' if @required
        parts << "in #{inclusion.inspect}" if @inclusion
        parts << 'strict' if @strict
        parts.join(', ')
      end

      private

      def normalize_type(type)
        return nil if type.nil?

        if type.is_a?(Symbol)
          unless SYMBOL_TYPES.key?(type)
            raise InvalidDefinition,
                  "unsupported response_field type #{type.inspect} for :#{@name} " \
                  "(supported symbols: #{SYMBOL_TYPES.keys.join(', ')})"
          end
          return SYMBOL_TYPES[type]
        end

        unless type.is_a?(Class)
          raise InvalidDefinition,
                "unsupported response_field type #{type.inspect} for :#{@name} " \
                '(expected a Class or a supported symbol)'
        end

        type
      end

      def validate_definition!
        return unless @inclusion && !@inclusion.respond_to?(:include?)

        raise InvalidDefinition,
              "response_field :#{@name}: inclusion must respond to #include? " \
              "(got #{@inclusion.inspect})"
        
      end

      def type_violations(value)
        return [] unless @type

        case @type
        when :boolean
          unless value.equal?(true) || value.equal?(false)
            return ["field :#{@name} expected boolean, got #{value.class}"]
          end
        when :number
          return ["field :#{@name} expected number, got #{value.class}"] unless value.is_a?(Numeric)
        else
          return ["field :#{@name} expected #{type_name}, got #{value.class}"] unless value.is_a?(@type)
        end
        []
      end

      def inclusion_violations(value)
        # Open-schema default: new enum members are additive data. Only an
        # explicitly strict field treats an unknown value as a violation.
        return [] unless @inclusion && @strict

        unless @inclusion.include?(value)
          return ["field :#{@name} value #{value.inspect} " \
                  "is not in #{@inclusion.inspect}"]
        end
        []
      end

      def type_name
        case @type
        when nil then 'untyped'
        when :boolean then 'boolean'
        when :number then 'number'
        when Class then @type.name || 'anonymous class'
        else @type.to_s
        end
      end
    end
  end
end
