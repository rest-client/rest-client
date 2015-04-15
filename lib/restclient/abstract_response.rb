require 'cgi'
require 'forwardable'

module RestClient

  module AbstractResponse
    extend Forwardable

    attr_reader :net_http_res, :args, :request

    def_delegators :abstract_response_resolver, :cookie_jar, :return!, :follow_redirection

    # HTTP status code
    def code
      @code ||= @net_http_res.code.to_i
    end

    # A hash of the headers, beautified with symbols and underscores.
    # e.g. "Content-type" will become :content_type.
    def headers
      @headers ||= AbstractResponse.beautify_headers(@net_http_res.to_hash)
    end

    # The raw headers.
    def raw_headers
      @raw_headers ||= @net_http_res.to_hash
    end

    def response_set_vars(net_http_res, args, request)
      @net_http_res = net_http_res
      @args = args
      @request = request
    end

    # Hash of cookies extracted from response headers
    def cookies
      hash = {}

      cookie_jar.cookies.each do |cookie|
        hash[cookie.name] = cookie.value
      end

      hash
    end

    def to_i
      warn('warning: calling Response#to_i is not recommended')
      super
    end

    def description
      "#{code} #{STATUSES[code]} | #{(headers[:content_type] || '').gsub(/;.*$/, '')} #{size} bytes\n"
    end


    # Convert headers hash into canonical form.
    #
    # Header names will be converted to lowercase symbols with underscores
    # instead of hyphens.
    #
    # Headers specified multiple times will be joined by comma and space,
    # except for Set-Cookie, which will always be an array.
    #
    # Per RFC 2616, if a server sends multiple headers with the same key, they
    # MUST be able to be joined into a single header by a comma. However,
    # Set-Cookie (RFC 6265) cannot because commas are valid within cookie
    # definitions. The newer RFC 7230 notes (3.2.2) that Set-Cookie should be
    # handled as a special case.
    #
    # http://tools.ietf.org/html/rfc2616#section-4.2
    # http://tools.ietf.org/html/rfc7230#section-3.2.2
    # http://tools.ietf.org/html/rfc6265
    #
    # @param headers [Hash]
    # @return [Hash]
    #
    def self.beautify_headers(headers)
      headers.inject({}) do |out, (key, value)|
        key_sym = key.gsub(/-/, '_').downcase.to_sym

        # Handle Set-Cookie specially since it cannot be joined by comma.
        if key.downcase == 'set-cookie'
          out[key_sym] = value
        else
          out[key_sym] = value.join(', ')
        end

        out
      end
    end

    private

    def abstract_response_resolver
      AbstractResponseResolver.new(self)
    end

  end
end
