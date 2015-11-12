module RestClient
  # Various utility methods
  module Utils

    # Return encoding from an HTTP header hash.
    #
    # We use the RFC 7231 specification and do not impose a default encoding on
    # text. This differs from the older RFC 2616 behavior, which specifies
    # using ISO-8859-1 for text/* content types without a charset.
    #
    # Strings will effectively end up using `Encoding.default_external` when
    # this method returns nil.
    #
    # @param headers [Hash]
    #
    # @return [String, nil] encoding Return the string encoding or nil if no
    #   header is found.
    #
    def self.get_encoding_from_headers(headers)
      type_header = headers[:content_type]
      return nil unless type_header

      _content_type, params = cgi_parse_header(type_header)

      if params.include?('charset')
        return params.fetch('charset').gsub(/(\A["']*)|(["']*\z)/, '')
      end

      nil
    end

    # Parse semi-colon separated, potentially quoted header string iteratively.
    #
    # @private
    #
    def self._cgi_parseparam(s)
      return enum_for(__method__, s) unless block_given?

      while s[0] == ';'
        s = s[1..-1]
        ends = s.index(';')
        while ends && ends > 0 \
              && (s[0...ends].count('"') -
                  s[0...ends].scan('\"').count) % 2 != 0
          ends = s.index(';', ends + 1)
        end
        if ends.nil?
          ends = s.length
        end
        f = s[0...ends]
        yield f.strip
        s = s[ends..-1]
      end
      nil
    end

    # Parse a Content-type like header.
    #
    # Return the main content-type and a hash of options.
    #
    # This method was ported directly from Python's cgi.parse_header(). It
    # probably doesn't read or perform particularly well in ruby.
    # https://github.com/python/cpython/blob/3.4/Lib/cgi.py#L301-L331
    #
    #
    # @param [String] line
    # @return [Array(String, Hash)]
    #
    def self.cgi_parse_header(line)
      parts = _cgi_parseparam(';' + line)
      key = parts.next
      pdict = {}

      begin
        while (p = parts.next)
          i = p.index('=')
          if i
            name = p[0...i].strip.downcase
            value = p[i+1..-1].strip
            if value.length >= 2 && value[0] == '"' && value[-1] == '"'
              value = value[1...-1]
              value = value.gsub('\\\\', '\\').gsub('\\"', '"')
            end
            pdict[name] = value
          end
        end
      rescue StopIteration
      end

      [key, pdict]
    end

    # Serialize a ruby object into HTTP query string parameters.
    #
    # There is no standard for doing this, so we choose our own slightly
    # idiosyncratic format. The output closely matches the format understood by
    # Rails, Rack, and PHP.
    #
    # If you don't want handling of complex objects and only want to handle
    # simple flat hashes, you may want to use `URI.encode_www_form` instead,
    # which implements HTML5-compliant URL encoded form data.
    #
    # @param [Object] object The object to serialize
    # @param [String] parent_key The parent hash key of this object
    #
    # @return [String] A string appropriate for use as an HTTP query string
    #
    # @see URI.encode_www_form
    #
    # @see See also Object#to_query in ActiveSupport
    # @see http://php.net/manual/en/function.http-build-query.php
    #   http_build_query in PHP
    # @see See also Rack::Utils.build_nested_query in Rack
    #
    # Notable differences from the ActiveSupport implementation:
    #
    # - Empty hash and empty array are treated the same as nil instead of being
    #   omitted entirely from the output. Rather than disappearing, they will
    #   appear to be nil instead.
    #
    # @since 2.0.0
    #
    # @example Simple hashes
    #   >> encode_query_string({foo: 123, bar: 456})
    #   => 'foo=123&bar=456'
    #
    # @example Simple arrays
    #   >> encode_query_string({foo: [1,2,3]})
    #   => 'foo[]=1&foo[]=2&foo[]=3'
    #
    # @example Nested hashes
    #   >> encode_query_string({outer: {foo: 123, bar: 456}})
    #   => 'outer[foo]=123&outer[bar]=456'
    #
    # @example Null and empty values
    #   >> encode_query-string({string: '', empty: nil, list: [], hash: {}})
    #   => 'string=&empty&list&hash'
    #
    # @example Nested nulls
    #   >> encode_query-string({foo: {string: '', empty: nil}})
    #   => 'foo[string]=&foo[empty]'
    #
    def self.encode_query_string(object, parent_key=nil)
      if !parent_key && !object.is_a?(Hash)
        raise ArgumentError.new('top level query param must be a Hash, got: ' +
                                object.inspect)
      end

      case object
      when Hash
        if object.empty?
          if parent_key
            return encode_query_string(nil, parent_key)
          else
            return ''
          end
        end

        return object.map { |k, v|
          k = CGI.escape(k.to_s)
          encode_query_string(v, parent_key ? "#{parent_key}[#{k}]" : k)
        }.join('&')

      when Array
        if object.empty?
          return encode_query_string(nil, parent_key)
        end

        prefix = "#{parent_key}[]"
        return object.map {|v| encode_query_string(v, prefix) }.join('&')

      when nil
        parent_key.to_s

      else
        "#{parent_key}=#{CGI.escape(object.to_s)}"
      end
    end

    # TODO: figure out whether escape should be CGI.escape or
    # URI.encode_www_form_component
  end
end
