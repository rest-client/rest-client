module RestClient
  # Various utility methods
  module Utils

    # Return encoding from an HTTP header hash.
    #
    # @param headers [Hash]
    #
    # @return [String] encoding
    #
    def self.get_encoding_from_headers(headers)
      type_header = headers[:content_type]
      return nil unless type_header

      content_type, params = cgi_parse_header(type_header)

      if params.include?('charset')
        return params.fetch('charset').gsub(/(\A["']*)|(["']*\z)/, '')
      end

      # HTTP typically defaults to ISO-8859-1 when not specified.
      if content_type.include?('text')
        return 'ISO-8859-1'
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
        while p = parts.next
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
  end
end
