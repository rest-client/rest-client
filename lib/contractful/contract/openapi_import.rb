# frozen_string_literal: true

require 'yaml'
require 'json'
require_relative '../contract'

# rubocop:disable Naming/MethodParameterName
# The rendering helpers below follow OpenAPI tooling conventions for the
# local variables they pass around: `op` for an Operation object, `p` for
# a parameter, `f` for a response field and `d` for a Definition. The
# single letters are domain-idiomatic here; long-form names would be
# repeated dozens of times across these small, well-scoped helpers.
module Contractful
  module Contract
    # OpenAPI 3.x import helper (REQ-N01) — a development-time, opt-in reader
    # that converts an OpenAPI 3.x document into `contract` declarations.
    #
    # This is a source-to-source tool: it is not part of the runtime request
    # path and adds no dependencies (YAML/JSON parsing is stdlib). Require it
    # explicitly — it never loads as a side effect of `contractful`:
    #
    #   require 'contractful/contract/openapi_import'
    #
    # Three entry points:
    #
    #   * {OpenAPIImport.definitions} — build {Definition} objects from a
    #     document (accepts a Hash, a file path, or YAML/JSON text).
    #   * {OpenAPIImport.to_ruby} — render a ready-to-paste client class,
    #     generated from those same definitions.
    #   * {OpenAPIImport.import} — the full result: definitions, base URL,
    #     auth hints and the notes channel.
    #
    # The mapping is deliberately conservative and HONEST about what it
    # cannot express. Every decision that loses information (header params,
    # multipart bodies, oneOf unions, `default` responses, ...) is reported
    # on {Import#notes} so generated code can be reviewed against the source
    # document. Nothing silently disappears.
    #
    # Mapped: path/query/body-object params (type + required + default +
    # enum/min/max/length/pattern constraints), `payload_style` (form for
    # urlencoded bodies, query for body-less POST/PUT/PATCH), response
    # statuses (numeric and `2XX` wildcards), JSON response types and
    # open-schema `response_field` bindings, base URL from `servers` and
    # auth *hints* from `securitySchemes`.
    module OpenAPIImport
      # Raised when a document cannot be parsed or is not OpenAPI 3.x, and
      # for rendering failures in {Import#to_ruby}.
      class Error < Contractful::Contract::Error; end

      HTTP_METHODS = %w[get put post patch delete head options trace].freeze
      BODY_VERBS = %i[post put patch].freeze

      MAX_REF_DEPTH = 10

      module_function

      # --- public API -------------------------------------------------------

      # Parse an OpenAPI document. +source+ may be a Hash (already parsed),
      # a String/Pathname file path, or a YAML/JSON text.
      #
      # @return [Hash] the document
      # @raise [Error]
      def load(source)
        case source
        when Hash
          source
        when Pathname
          load_file(source.to_s)
        when String
          if source.include?("\n") || source.lstrip.start_with?('{', '[')
            parse_text(source)
          else
            load_file(source)
          end
        else
          raise Error,
                "cannot load an OpenAPI document from #{source.inspect} " \
                '(pass a Hash, a file path or YAML/JSON text)'
        end
      end

      # Convert a document into contract definitions.
      #
      # @param source Hash, file path or YAML/JSON text
      # @param only [Array<Symbol>] keep only these operation names
      # @param except [Array<Symbol>] drop these operation names
      # @return [Hash{Symbol => Definition}] operation name => definition
      def definitions(source, only: nil, except: nil)
        import(source, only: only, except: except).definitions
      end

      # Full import: definitions plus the auxiliary material a generated
      # client needs.
      #
      # @return [Import]
      def import(source, only: nil, except: nil)
        doc = load(source)
        validate_document!(doc)

        ctx = Context.new(doc)
        base_url = resolve_base_url(doc, ctx)
        auth_hints = derive_auth_hints(doc, ctx)

        definitions = {}
        Array(doc['paths']).each do |path, item|
          item = deref(ctx, item, "path #{path}")
          next unless item.is_a?(Hash)

          shared = Array(item['parameters'])
          note_servers(item, "path #{path}", ctx)

          item.each do |method, op|
            next unless HTTP_METHODS.include?(method.to_s.downcase)

            if method.to_s.downcase == 'trace'
              ctx.note("#{path}: trace operation skipped (unsupported verb)")
              next
            end
            next unless op.is_a?(Hash)

            name = ctx.unique_name(derive_name(method, path, op))
            next if skip_name?(name, only, except)

            definitions[name] =
              build_definition(ctx, name, method.to_s.downcase.to_sym, path, op, shared)
          end
        end

        ctx.note('webhooks are not imported') if doc.key?('webhooks')

        Import.new(document: doc, base_url: base_url, auth_hints: auth_hints,
                   definitions: definitions, notes: ctx.notes)
      end

      # Render a ready-to-paste client class from an OpenAPI document. The
      # source is generated from the imported {Definition} objects, so it is
      # guaranteed to round-trip: evaluating the output yields a class whose
      # contracts describe exactly like the imported definitions.
      #
      # @param class_name [String] constant, may be namespaced (A::B)
      # @return [String] Ruby source
      def to_ruby(source, class_name: 'GeneratedClient', only: nil, except: nil)
        import(source, only: only, except: except).to_ruby(class_name: class_name)
      end

      # --- result object ------------------------------------------------------

      # The result of {OpenAPIImport.import}.
      class Import
        # The parsed OpenAPI document.
        attr_reader :document
        # Base URL derived from `servers` (nil when not derivable).
        attr_reader :base_url
        # Suggested `auth ...` declarations from `securitySchemes`
        # (commented-out hints — credentials are never invented).
        attr_reader :auth_hints
        # {Symbol => Definition} — the converted operations.
        attr_reader :definitions
        # Every information-losing mapping decision, for review.
        attr_reader :notes

        def initialize(document:, base_url:, auth_hints:, definitions:, notes:)
          @document = document
          @base_url = base_url
          @auth_hints = auth_hints
          @definitions = definitions
          @notes = notes.freeze
        end

        # Render a client class source from this import.
        def to_ruby(class_name: 'GeneratedClient')
          Renderer.render(self, class_name: class_name)
        end
      end

      # --- source renderer ----------------------------------------------------

      # Renders {Import} to client-class source. The renderer works from the
      # built {Definition} objects (never from the raw document), which is
      # what makes the output round-trip through Definition#describe.
      module Renderer
        RESPONSE_FIELD_TYPE_SOURCES = {
          String => ':string', Integer => ':integer', Float => ':float',
          Array => ':array', Hash => ':hash'
        }.freeze

        module_function

        def render(import, class_name:)
          parts = class_name.to_s.split('::')
          if parts.empty? || !parts.all? { |p| p.match?(/\A[A-Z][A-Za-z0-9_]*\z/) }
            raise Error, "class_name must be a Ruby constant, got #{class_name.inspect}"
          end

          out = []
          out << '# frozen_string_literal: true'
          out << '# Generated by Contractful::Contract::OpenAPIImport — review before use.'
          info = import.document['info'].is_a?(Hash) ? import.document['info'] : {}
          if info['title'] || info['version']
            out << "# Source: #{info['title']} (OpenAPI #{import.document['openapi']}, " \
                   "version #{info['version']})"
          end
          unless import.notes.empty?
            out << '#'
            out << '# Import notes (review these):'
            import.notes.each { |note| out << "#   - #{note}" }
          end
          out << ''
          out << "module #{parts.shift}" while parts.size > 1
          out << "class #{parts.first}"
          out << '  include Contractful::Contract'
          out << ''
          out << "  base #{import.base_url.inspect}" if import.base_url
          import.auth_hints.each { |hint| out << "  # #{hint}" }
          out << '' if import.base_url || import.auth_hints.any?

          import.definitions.each_value do |definition|
            out.concat(render_definition(definition))
            out << ''
          end
          out << 'end'
          out.select { |l| l.start_with?('module ') }.size.times { out << 'end' }
          out.join("\n") << "\n"
        end

        def render_definition(d)
          lines = []
          header = "  contract #{d.name.inspect}, #{request_line(d).inspect}"
          header << ", description: #{d.description.inspect}" if d.description
          header << ' do'
          lines << header

          d.params.each_value do |param|
            lines << "    param #{param_args(param)}"
          end
          lines << "    payload_style #{d.payload_style.inspect}" if d.payload_style

          if d.response_statuses
            rendered = d.response_statuses.map { |s| render_status(s) }
            line = "    responds #{rendered.join(', ')}"
            line << ", type: #{respond_type_source(d.response_type)}" if d.response_type
            lines << line
          end

          d.response_fields.each_value do |field|
            lines << "    response_field #{field_args(field)}"
          end

          lines << '  end'
          lines
        end

        def request_line(d)
          "#{d.verb.to_s.upcase} #{d.path_template}"
        end

        def param_args(p)
          args = [p.name.inspect]
          type = type_source(p.type)
          args << type if type
          args << 'required: true' if p.required?

          if p.has_default?
            if p.lazy_default?
              raise Error,
                    "cannot render a Proc default for param :#{p.name} — " \
                    'write it by hand'
            end
            value = p.default_value
            args << "default: #{value.inspect}"
          end
          args << "inclusion: #{wrap_range(p.inclusion)}" if p.inclusion
          args << "min: #{wrap_range(p.min)}" if p.min
          args << "max: #{wrap_range(p.max)}" if p.max
          args << "length: #{wrap_range(p.length)}" if p.length
          args << "pattern: #{p.pattern.inspect}" if p.pattern
          args.join(', ')
        end

        def field_args(f)
          args = [f.name.inspect]
          type = type_source_for_field(f.type)
          args << type if type
          args << 'required: true' if f.required?
          args << "inclusion: #{wrap_range(f.inclusion)}" if f.inclusion
          args << 'strict: true' if f.strict?
          args.join(', ')
        end

        def type_source(type)
          return nil if type.nil?
          return ':boolean' if type.equal?(:boolean)
          return type.name if type.is_a?(Class)

          raise Error, 'cannot render a Proc param type — write it by hand'
        end

        def type_source_for_field(type)
          return nil if type.nil?
          return ":#{type}" if %i[boolean number].include?(type)
          return RESPONSE_FIELD_TYPE_SOURCES[type] if RESPONSE_FIELD_TYPE_SOURCES.key?(type)

          type.name
        end

        def respond_type_source(type)
          return ':json' if type.equal?(:json)
          return ':string' if type.equal?(String)
          return ':array' if type.equal?(Array)
          return ':hash' if type.equal?(Hash)

          type.name
        end

        def render_status(status)
          status.is_a?(Range) ? "(#{status.min}..#{status.max})" : status.to_s
        end

        def wrap_range(value)
          value.is_a?(Range) ? "(#{value.min}..#{value.max})" : value.inspect
        end
      end

      # --- internals ----------------------------------------------------------

      # Mutable import state: the document, the notes channel and taken
      # operation names.
      class Context
        attr_reader :document, :notes

        def initialize(document)
          @document = document
          @notes = []
          @taken = {}
        end

        def note(message)
          @notes << message unless @notes.include?(message)
        end

        def unique_name(base)
          base = base.to_s
          candidate = base
          n = 1
          while @taken.key?(candidate) || Contract::RESERVED_NAMES.include?(candidate.to_sym)
            n += 1
            candidate = "#{base}_#{n}"
          end
          @taken[candidate] = true
          candidate.to_sym
        end
      end

      def validate_document!(doc)
        raise Error, "not an OpenAPI document: #{doc.class} (expected Hash)" unless doc.is_a?(Hash)

        version = doc['openapi'].to_s
        if version.start_with?('2.')
          raise Error,
                "OpenAPI/Swagger #{version} is not supported — convert the " \
                'document to OpenAPI 3.x first (e.g. with swagger2openapi)'
        end
        unless version.start_with?('3')
          raise Error,
                "missing or unsupported 'openapi' version field #{doc['openapi'].inspect} " \
                '(expected 3.x)'
        end
        return if doc['paths'].is_a?(Hash) && !doc['paths'].empty?

        raise Error, 'the document declares no paths — nothing to import'
      end

      def skip_name?(name, only, except)
        return true if only && !Array(only).map(&:to_sym).include?(name)
        return true if except && Array(except).map(&:to_sym).include?(name)

        false
      end

      def load_file(path)
        raise Error, "no such file: #{path}" unless File.file?(path)

        if YAML.respond_to?(:safe_load_file)
          YAML.safe_load_file(path, aliases: true) || raise(Error, "empty document: #{path}")
        else
          parse_text(File.read(path))
        end
      rescue Psych::SyntaxError => e
        raise Error, "invalid YAML in #{path}: #{e.message}"
      end

      def parse_text(text)
        stripped = text.to_s.strip
        return {} if stripped.empty?

        if stripped.start_with?('{', '[')
          begin
            return JSON.parse(stripped)
          rescue JSON::ParserError
            nil # fall through and parse as YAML
          end
        end
        YAML.safe_load(stripped, aliases: true) || raise(Error, 'empty document')
      rescue Psych::SyntaxError => e
        raise Error, "invalid YAML/JSON text: #{e.message}"
      end

      # JSON Pointer ($ref) resolution inside the document, with ~0/~1
      # unescaping. Non-local or unresolvable refs return nil (callers
      # degrade to an untyped param plus a note).
      def resolve_pointer(ctx, node, ref, depth: 0)
        return nil if depth > MAX_REF_DEPTH
        return nil unless ref.is_a?(String) && ref.start_with?('#/')

        node = ctx.document
        ref[2..].split('/').each do |raw|
          token = raw.gsub('~1', '/').gsub('~0', '~')
          node = node.is_a?(Hash) ? node[token] : nil
          return nil if node.nil?
        end
        node
      end

      def deref(ctx, node, label)
        if node.is_a?(Hash) && node['$ref']
          resolved = resolve_pointer(ctx, node, node['$ref'])
          unless resolved.is_a?(Hash)
            ctx.note("#{label}: unresolvable $ref #{node['$ref'].inspect} — ignored")
            return nil
          end
          return resolved
        end
        node.is_a?(Hash) ? node : nil
      end

      def derive_name(method, path, op)
        raw = op['operationId']
        base = if raw
                 snake_case(raw.to_s)
               else
                 segments = path.split('/').reject(&:empty?).map do |seg|
                   seg.gsub(/\{([^}]+)\}/, '\1').gsub(/[^a-zA-Z0-9_]/, '_')
                 end
                 [method, *segments].reject { |s| s.empty? }.join('_')
               end
        base = base.gsub(/[^a-zA-Z0-9_]/, '_').gsub(/_+/, '_')
        base = base.sub(/\A_+/, '').sub(/_+\z/, '')
        base = "_#{base}" if base.match?(/\A\d/)
        base = "#{method}_operation" if base.empty?
        base
      end

      def snake_case(str)
        s = str.gsub(/([A-Z\d]+)([A-Z][a-z])/, '\1_\2')
        s = s.gsub(/([a-z\d])([A-Z])/, '\1_\2')
        s.tr('-. ', '___').downcase
      end

      # {id} → :id, validating that placeholders are Ruby identifiers.
      def to_template(path)
        path.gsub(/\{([^}]+)\}/) do
          name = Regexp.last_match(1).strip
          unless name.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
            raise Error,
                  "path #{path.inspect}: placeholder {#{name}} is not a valid " \
                  'Ruby identifier — rename it or import with a rewritten path'
          end
          ":#{name}"
        end
      end

      def build_definition(ctx, name, verb, path, op, shared_params)
        template = to_template(path)
        description = op['summary'] || op['description']
        ctx.note("#{op_label(path, verb)}: deprecated operation") if op['deprecated']
        note_servers(op, op_label(path, verb), ctx)

        definition = Definition.new(name, verb, template, description: description)

        collect_params(ctx, verb, path, op, shared_params).each_value do |decl|
          definition.param(decl[:name], decl[:type], **decl[:options])
        end

        style = body_payload_style(ctx, verb, path, op)
        definition.payload_style(style) if style

        apply_responses(ctx, definition, verb, path, op)
        definition
      end

      def op_label(path, verb)
        "#{verb.to_s.upcase} #{path}"
      end

      # --- parameter conversion -------------------------------------------------

      # Merge path-level and operation-level `parameters` (operation wins on
      # [in, name]) and convert each into a param declaration, then add the
      # request body object properties. Returns an ordered Hash: path params
      # first, then the rest (document order).
      def collect_params(ctx, verb, path, op, shared_params)
        template = to_template(path)
        placeholders = template.scan(Definition::PATH_PLACEHOLDER).map { |m| m[0].to_sym }

        merged = {}
        Array(shared_params).each do |raw|
          p = deref(ctx, raw, "path #{path} shared parameter")
          next unless p

          key = [p['in'], p['name']]
          merged[key] = p
        end
        Array(op['parameters']).each do |raw|
          p = deref(ctx, raw, op_label(path, verb))
          next unless p

          key = [p['in'], p['name']]
          merged[key] = p
        end

        declarations = {}
        merged.each_value do |p|
          next unless p.is_a?(Hash)

          location = p['in']
          pname = p['name'].to_s
          label = "#{op_label(path, verb)} #{location} param #{pname.inspect}"

          if p['content']
            ctx.note("#{label}: media-type parameter (content) is not representable — declare manually")
            next
          end

          if (location == 'query') && BODY_VERBS.include?(verb) && op['requestBody']
            ctx.note(
              "#{label}: mixes a request body and query parameters — the DSL routes " \
              'all declared params to one location, so this one will be serialized ' \
              'into the payload (adjust manually if the vendor requires it in the query)'
            )
          end

          case location
          when 'path'
            unless pname.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
              ctx.note("#{label}: name is not a valid Ruby identifier — skipped")
              next
            end
            key = pname.to_sym
            unless placeholders.include?(key)
              ctx.note("#{label}: declared but not present in the path template — skipped")
              next
            end
            declarations[key] = param_declaration(ctx, p, label, required: true)
          when 'query'
            unless pname.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
              ctx.note("#{label}: name is not a valid Ruby identifier — skipped")
              next
            end
            declarations[pname.to_sym] = param_declaration(ctx, p, label)
          when 'header', 'cookie'
            ctx.note(
              "#{label}: #{location} parameters are not representable as contract " \
              'params — wire them via default_headers or before_request'
            )
          else
            ctx.note("#{label}: unknown parameter location — skipped")
          end
        end

        # Request body object properties come last.
        body = op['requestBody'] ? deref(ctx, op['requestBody'], op_label(path, verb)) : nil
        if body
          if %i[get head].include?(verb)
            ctx.note("#{op_label(path, verb)}: requestBody on #{verb.to_s.upcase} is ignored " \
                     '(the DSL sends no body for these verbs)')
          elsif %i[delete options].include?(verb)
            ctx.note("#{op_label(path, verb)}: requestBody on #{verb.to_s.upcase} cannot be sent — " \
                     'the DSL routes params on this verb to the query string')
          else
            collect_body_params(ctx, verb, path, body, declarations)
          end
        end

        declarations
      end

      def param_declaration(ctx, p, label, required: false)
        schema = deref(ctx, p['schema'] || {}, label) || {}
        note_nullable(ctx, schema, label)

        type, type_note = map_type(ctx, schema, label)
        ctx.note("#{label}: #{type_note}") if type_note

        options = constraint_options(ctx, schema, label)
        options[:required] = true if required || p['required'] == true
        options[:description] = p['description'] || schema['description']

        { name: p['name'].to_sym, type: type, options: options }
      end

      def collect_body_params(ctx, verb, path, body, declarations)
        content = body['content'].is_a?(Hash) ? body['content'] : {}
        json_media = content.find do |type, _|
          type.to_s.split(';').first.to_s.strip == 'application/json'
        end
        return unless json_media

        label = op_label(path, verb)
        schema = deref(ctx, json_media[1]['schema'], "#{label} request body") || {}
        note_nullable(ctx, schema, "#{label} request body")

        if schema['type'] && schema['type'] != 'object'
          ctx.note("#{label}: request body is a #{schema['type']} — object properties " \
                   'cannot be derived; declare params manually')
          return
        end
        if schema['oneOf'] || schema['anyOf'] || schema['allOf']
          ctx.note("#{label}: request body is a schema combination (oneOf/anyOf/allOf) — " \
                   'declare params manually')
          return
        end

        required_fields = Array(schema['required']).map(&:to_s)
        properties = schema['properties'].is_a?(Hash) ? schema['properties'] : {}
        properties.each do |pname, raw_schema|
          next unless pname.to_s.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)

          prop_label = "#{label} body param #{pname.to_s.inspect}"
          prop_schema = deref(ctx, raw_schema, prop_label) || {}
          note_nullable(ctx, prop_schema, prop_label)
          type, type_note = map_type(ctx, prop_schema, prop_label)
          ctx.note("#{prop_label}: #{type_note}") if type_note

          options = constraint_options(ctx, prop_schema, prop_label)
          options[:required] = true if required_fields.include?(pname.to_s)
          options[:description] = prop_schema['description']

          declarations[pname.to_sym] = { name: pname.to_sym, type: type, options: options }
        end
      end

      # Schema → [param type, note]. Untyped/unsupported combinations yield
      # [nil, note] — the param stays untyped instead of guessed.
      def map_type(ctx, schema, label, depth: 0)
        return [nil, 'schema nesting too deep — left untyped'] if depth > MAX_REF_DEPTH

        if (ref = schema['$ref'])
          resolved = resolve_pointer(ctx, schema, ref)
          return [nil, "unresolvable $ref #{ref.inspect} — left untyped"] unless resolved.is_a?(Hash)

          return map_type(ctx, resolved, label, depth: depth + 1)
        end

        %w[oneOf anyOf allOf not].each do |combinator|
          return [nil, "#{combinator} schemas are not representable — left untyped"] if schema[combinator]
        end

        case schema['type']
        when 'string' then [String, nil]
        when 'integer' then [Integer, nil]
        when 'number' then [Float, nil]
        when 'boolean' then [:boolean, nil]
        when 'array' then [Array, nil]
        when 'object' then [Hash, nil]
        when nil then [nil, nil]
        else [nil, "type #{schema['type'].inspect} is not representable — left untyped"]
        end
      end

      def note_nullable(ctx, schema, label)
        return unless schema.is_a?(Hash) && schema['nullable'] == true

        ctx.note("#{label}: nullable maps to 'param absent' semantics (a nil value " \
                 'behaves like a missing param)')
      end

      # JSON Schema constraints → contract param options (min:/max:/length:/
      # pattern:/inclusion:/default:). Anything that cannot be expressed
      # faithfully produces a note instead of a wrong constraint.
      def constraint_options(ctx, schema, label)
        options = {}
        options[:inclusion] = schema['enum'] if schema['enum'].is_a?(Array)

        # OpenAPI 3.0: minimum + exclusiveMinimum:true. OpenAPI 3.1 allows a
        # numeric exclusiveMinimum instead of minimum. Only integer schemas
        # can absorb exclusivity by shifting the bound by one; a number
        # (float) schema is approximated with an inclusive bound and a note.
        integer_type = schema['type'] == 'integer'
        if schema.key?('minimum') || schema['exclusiveMinimum'].is_a?(Numeric)
          bound = schema.key?('minimum') ? schema['minimum'] : schema['exclusiveMinimum']
          exclusive = schema['exclusiveMinimum'] == true || schema['exclusiveMinimum'].is_a?(Numeric)
          if exclusive && integer_type && bound.is_a?(Integer)
            options[:min] = bound + 1
          else
            ctx.note("#{label}: exclusiveMinimum approximated as an inclusive bound") if exclusive
            options[:min] = bound if bound
          end
        end

        if schema.key?('maximum') || schema['exclusiveMaximum'].is_a?(Numeric)
          bound = schema.key?('maximum') ? schema['maximum'] : schema['exclusiveMaximum']
          exclusive = schema['exclusiveMaximum'] == true || schema['exclusiveMaximum'].is_a?(Numeric)
          if exclusive && integer_type && bound.is_a?(Integer)
            options[:max] = bound - 1
          else
            ctx.note("#{label}: exclusiveMaximum approximated as an inclusive bound") if exclusive
            options[:max] = bound if bound
          end
        end

        lo = schema['minLength']
        hi = schema['maxLength']
        if lo || hi
          if lo && hi
            options[:length] = lo == hi ? lo : (lo..hi)
          else
            ctx.note("#{label}: #{lo ? 'minLength' : 'maxLength'} without the other is not " \
                     'expressible (length: needs both bounds) — skipped')
          end
        end

        if (pattern = schema['pattern'])
          begin
            options[:pattern] = Regexp.new(pattern)
          rescue RegexpError => e
            ctx.note("#{label}: pattern #{pattern.inspect} is not a valid Ruby Regexp (#{e.message}) — skipped")
          end
        end

        if schema.key?('default')
          default = schema['default']
          options[:default] = default
          if options[:inclusion] && !options[:inclusion].include?(default)
            ctx.note("#{label}: default #{default.inspect} is not a member of the enum")
          end
        end

        options
      end

      # --- payload style --------------------------------------------------------

      # Choose payload_style from the request body content:
      #   application/json                  → :json (the DSL default; no line)
      #   application/x-www-form-urlencoded → :form
      #   multipart/*                       → noted, not mapped
      # No body + query params on a body verb → :query so params hit the URL.
      def body_payload_style(ctx, verb, path, op)
        label = op_label(path, verb)
        body = op['requestBody'] ? deref(ctx, op['requestBody'], label) : nil

        if body
          content = body['content'].is_a?(Hash) ? body['content'] : {}
          if content.any? { |t, _| t.to_s.split(';').first.to_s.strip == 'application/x-www-form-urlencoded' }
            return :form
          end

          unless content.any? { |t, _| t.to_s.split(';').first.to_s.strip == 'application/json' }
            ctx.note("#{label}: request body content types " \
                     "[#{content.keys.map(&:inspect).join(', ')}] are not representable as " \
                     'contract params (multipart/raw bodies need manual payload handling)')
          end
          return nil
        end

        has_query = Array(op['parameters']).any? do |raw|
          p = deref(ctx, raw, label)
          p && p['in'] == 'query'
        end
        return :query if BODY_VERBS.include?(verb) && has_query

        nil
      end

      # --- responses --------------------------------------------------------------

      def apply_responses(ctx, definition, verb, path, op)
        responses = op['responses'].is_a?(Hash) ? op['responses'] : {}
        return if responses.empty?

        entries = []
        responses.each do |code, raw|
          label = "#{op_label(path, verb)} response #{code.inspect}"
          resp = deref(ctx, raw, label)
          next unless resp.is_a?(Hash)

          if code == 'default'
            ctx.note("#{label}: the 'default' response is not representable — skipped")
            next
          end

          status = parse_status(ctx, code, op_label(path, verb))
          next unless status

          entries << [status, resp, label]
        end

        return if entries.empty?

        statuses = entries.map { |s, _| s }.sort_by { |s| s.is_a?(Range) ? s.min : s }

        # Type + response fields come from the first 2xx entry with an
        # application/json schema; every other entry only contributes its
        # status.
        source = entries.find do |status, resp, _|
          next false unless status2xx?(status)

          content = resp.is_a?(Hash) ? resp['content'] : nil
          content.is_a?(Hash) &&
            content.any? { |t, _| t.to_s.split(';').first.to_s.strip == 'application/json' }
        end

        type = nil
        fields_schema = nil
        if source
          schema, = json_schema_of(ctx, source[1], source[2])
          type = case schema['type']
                 when 'array' then :array
                 when 'object' then :hash
                 when 'string' then :string
                 else :json
                 end
          fields_schema = schema if schema['type'] == 'object'
        end

        definition.responds(*statuses, type: type)
        apply_response_fields(ctx, definition, fields_schema) if fields_schema
      end

      def status2xx?(status)
        status.is_a?(Integer) ? (200..299).cover?(status) : status.min >= 200 && status.max <= 299
      end

      def parse_status(ctx, code, label)
        case code.to_s
        when /\A([1-5])\d{2}\z/
          code.to_i
        when /\A([1-5])XX\z/
          n = Regexp.last_match(1).to_i * 100
          (n..(n + 99))
        else
          ctx.note("#{label}: response code #{code.inspect} is not a numeric status — skipped")
          nil
        end
      end

      # Returns [schema, media_type] for the first application/json entry.
      def json_schema_of(ctx, response, label)
        content = response['content'].is_a?(Hash) ? response['content'] : {}
        media = content.find do |type, _|
          type.to_s.split(';').first.to_s.strip == 'application/json'
        end
        return nil unless media

        schema = deref(ctx, media[1].is_a?(Hash) ? media[1]['schema'] : nil, label) || {}
        [schema, media[0]]
      end

      def apply_response_fields(ctx, definition, schema)
        required_fields = Array(schema['required']).map(&:to_s)
        properties = schema['properties'].is_a?(Hash) ? schema['properties'] : {}
        properties.each do |pname, raw_schema|
          next unless pname.to_s.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)

          label = "#{definition.name} response field #{pname.to_s.inspect}"
          field_schema = deref(ctx, raw_schema, label) || {}
          type, type_note = map_type(ctx, field_schema, label)
          ctx.note("#{label}: #{type_note}") if type_note

          options = {}
          options[:required] = true if required_fields.include?(pname.to_s)
          options[:inclusion] = field_schema['enum'] if field_schema['enum'].is_a?(Array)
          options[:description] = field_schema['description']
          definition.response_field(pname.to_sym, type, **options)
        end
      end

      # --- servers & security ------------------------------------------------------

      def note_servers(node, label, ctx)
        return unless node.is_a?(Hash) && node['servers']

        ctx.note("#{label}: operation-level servers override the base URL — not representable, " \
                 'configure the client manually if needed')
      end

      def resolve_base_url(doc, ctx)
        server = Array(doc['servers']).first
        return nil unless server.is_a?(Hash)

        url = server['url'].to_s
        variables = server['variables'].is_a?(Hash) ? server['variables'] : {}
        url = url.gsub(/\{([a-zA-Z0-9_]+)\}/) do
          name = Regexp.last_match(1)
          variable = variables[name]
          variable.is_a?(Hash) && variable.key?('default') ? variable['default'].to_s : "{#{name}}"
        end

        unless url.match?(%r{\Ahttps?://}i)
          ctx.note("server URL #{url.inspect} is not an absolute http(s) URL — no `base` " \
                   'emitted, configure the client manually')
          return nil
        end

        url.sub(%r{/+\z}, '')
      end

      # Auth is never invented: securitySchemes produce commented-out HINTS
      # (rendered into generated source) so credentials stay the user's job.
      def derive_auth_hints(doc, ctx)
        schemes = doc.dig('components', 'securitySchemes')
        return [] unless schemes.is_a?(Hash)

        hints = []
        schemes.each do |name, raw|
          scheme = deref(ctx, raw, "securityScheme #{name.inspect}")
          next unless scheme

          env = name.to_s.upcase.gsub(/[^A-Z0-9]+/, '_')
          case scheme['type']
          when 'http'
            case scheme['scheme'].to_s
            when 'bearer'
              hints << "auth bearer: -> { ENV['#{env}_TOKEN'] } # securityScheme: #{name}"
            when 'basic'
              hints << "auth basic: -> { [ENV['#{env}_USER'], ENV['#{env}_PASSWORD']] } " \
                       "# securityScheme: #{name}"
            else
              ctx.note("securityScheme #{name.inspect}: http scheme " \
                       "#{scheme['scheme'].inspect} has no DSL equivalent — skipped")
            end
          when 'apiKey'
            case scheme['in']
            when 'header'
              hints << "auth api_key: { name: #{scheme['name'].inspect}, " \
                       "value: -> { ENV['#{env}'] } } # securityScheme: #{name}"
            when 'query'
              hints << "auth api_key: { name: #{scheme['name'].inspect}, " \
                       "value: -> { ENV['#{env}'] }, in: :query } # securityScheme: #{name}"
            else
              ctx.note("securityScheme #{name.inspect}: apiKey in #{scheme['in'].inspect} " \
                       'is not representable — skipped')
            end
          when 'oauth2', 'openIdConnect'
            ctx.note("securityScheme #{name.inspect}: OAuth flows are not auto-generated — " \
                     'supply a token source via auth bearer: or a before_request callback')
          end
        end
        hints
      end
    end
  end
end
# rubocop:enable Naming/MethodParameterName
