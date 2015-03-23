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

    def self.beautify_headers(headers)
      headers.inject({}) do |out, (key, value)|
        out[key.gsub(/-/, '_').downcase.to_sym] = %w{ set-cookie }.include?(key.downcase) ? value : value.first
        out
      end
    end

    private

    def abstract_response_resolver
      AbstractResponseResolver.new(self)
    end

    # Parse a cookie value and return its content in an Hash
    def parse_cookie cookie_content
      out = {}
      CGI::Cookie::parse(cookie_content).each do |key, cookie|
        unless ['expires', 'path'].include? key
          out[CGI::escape(key)] = cookie.value[0] ? (CGI::escape(cookie.value[0]) || '') : ''
        end
      end
      out
    end

  end

end
