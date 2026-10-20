# frozen_string_literal: true

require 'cgi'
require 'http-cookie'

# Mixin giving responses (and raw responses) their shared accessors and
# behavior: status/header/body inspection, cookie handling and return
# semantics.
module Contractful
  # Response behavior shared by Response and RawResponse: status and header
  # inspection, cookie handling, redirection history and return semantics.
  module AbstractResponse
    # Headers that must never be forwarded to a different origin when
    # following a redirect (RFC 9110 §15.4: a client should not forward
    # credentials to a third party).
    SENSITIVE_REDIRECT_HEADERS = %w[authorization proxy-authorization cookie].freeze

    attr_reader :net_http_res, :request, :start_time, :end_time, :duration

    def inspect
      raise NotImplementedError.new('must override in subclass')
    end

    # Logger from the request, potentially nil.
    def log
      request.log
    end

    def log_response
      return unless log

      code = net_http_res.code
      res_name = net_http_res.class.to_s.gsub(/\ANet::HTTP/, '')
      content_type = (net_http_res['Content-type'] || '').gsub(/;.*\z/, '')

      log << "# => #{code} #{res_name} | #{content_type} #{size} bytes, #{format('%.2f', duration)}s\n"
    end

    # HTTP status code
    def code
      @code ||= @net_http_res.code.to_i
    end

    def history
      @history ||= request.redirection_history || []
    end

    # A hash of the headers, beautified with symbols and underscores.
    # e.g. "Content-type" will become :content_type.
    def headers
      @headers ||= AbstractResponse.beautify_headers(@net_http_res.to_hash)
    end

    # Parsed rate-limit information ({Contractful::RateLimit}), or nil when
    # the server did not send any rate-limit headers. Memoized.
    def rate_limit
      @rate_limit ||= RateLimit.from_headers(headers)
    end

    # True when the response indicates rate limiting: a 429 status, or a
    # server-reported remaining quota of zero.
    def rate_limited?
      return true if code == 429

      rate_limit ? rate_limit.exhausted? : false
    end

    # The raw headers.
    def raw_headers
      @raw_headers ||= @net_http_res.to_hash
    end

    # @param [Net::HTTPResponse] net_http_res
    # @param [Contractful::Request] request
    # @param [Time] start_time
    def response_set_vars(net_http_res, request, start_time)
      @net_http_res = net_http_res
      @request = request
      @start_time = start_time
      @end_time = Time.now

      @duration = @start_time ? @end_time - @start_time : nil

      # prime redirection history
      history
    end

    # Hash of cookies extracted from response headers.
    #
    # NB: This will return only cookies whose domain matches this request, and
    # may not even return all of those cookies if there are duplicate names.
    # Use the full cookie_jar for more nuanced access.
    #
    # @see #cookie_jar
    #
    # @return [Hash]
    #
    def cookies
      hash = {}

      cookie_jar.cookies(@request.uri).each do |cookie|
        hash[cookie.name] = cookie.value
      end

      hash
    end

    # Cookie jar extracted from response headers.
    #
    # @return [HTTP::CookieJar]
    #
    def cookie_jar
      return @cookie_jar if defined?(@cookie_jar) && @cookie_jar

      jar = @request.cookie_jar.dup
      headers.fetch(:set_cookie, []).each do |cookie|
        jar.parse(cookie, @request.uri)
      end

      @cookie_jar = jar
    end

    # Return the default behavior corresponding to the response code:
    #
    # For 2xx status codes: return the response itself
    #
    # For 30x status codes:
    #   301, 302, 307: redirect GET / HEAD if there is a Location header
    #   303: redirect, changing method to GET, if there is a Location header
    #
    # For all other responses, raise a response exception
    #
    def return!(&block)
      case code
      when 200..299
        self
      when 301, 302, 307
        case request.method
        when 'get', 'head'
          check_max_redirects
          follow_redirection(&block)
        else
          raise exception_with_response
        end
      when 303
        check_max_redirects
        follow_get_redirection(&block)
      else
        raise exception_with_response
      end
    end

    def to_i
      warn('warning: calling Response#to_i is not recommended')
      super
    end

    def description
      "#{code} #{STATUSES[code]} | #{(headers[:content_type] || '').gsub(/;.*$/, '')} #{size} bytes\n"
    end

    # Follow a redirection response by making a new HTTP request to the
    # redirection target.
    def follow_redirection(&block)
      _follow_redirection(request.args.dup, &block)
    end

    # Follow a redirection response, but change the HTTP method to GET and drop
    # the payload from the original request.
    def follow_get_redirection(&block)
      new_args = request.args.dup
      new_args[:method] = :get
      new_args.delete(:payload)

      _follow_redirection(new_args, &block)
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
      headers.each_with_object({}) do |(key, value), out|
        key_sym = key.tr('-', '_').downcase.to_sym

        # Handle Set-Cookie specially since it cannot be joined by comma.
        out[key_sym] =
          if key.downcase == 'set-cookie'
            value
          else
            value.join(', ')
          end
      end
    end

    private

    # Follow a redirection
    #
    # @param new_args [Hash] Start with this hash of arguments for the
    #   redirection request. The hash will be mutated, so be sure to dup any
    #   existing hash that should not be modified.
    #
    def _follow_redirection(new_args, &block)
      # parse location header and merge into existing URL
      location = headers[:location]

      # cannot follow redirection if there is no location header
      raise exception_with_response unless location

      target = URI.parse(location)
      target = request.uri.merge(target) unless target.absolute?

      # Never downgrade an encrypted request to plaintext.
      raise exception_with_response if request.uri.scheme == 'https' && target.scheme == 'http'

      new_args[:url] = target.to_s

      if same_origin?(request.uri, target)
        new_args[:password] = request.password
        new_args[:user] = request.user
        new_args[:headers] = request.headers
      else
        # A redirect to another origin must not receive the caller's
        # credentials (basic auth or an explicit Authorization/Cookie header).
        new_args.delete(:user)
        new_args.delete(:password)
        new_args[:headers] = without_sensitive_headers(request.headers)
      end
      new_args[:max_redirects] = request.max_redirects - 1

      # pass through our new cookie jar
      new_args[:cookies] = cookie_jar

      # prepare new request
      new_req = Request.new(new_args)

      # append self to redirection history
      new_req.redirection_history = history + [self]

      # execute redirected request
      new_req.execute(&block)
    end

    def same_origin?(from, to)
      from.scheme == to.scheme && from.host == to.host && from.port == to.port
    end

    def without_sensitive_headers(headers)
      headers.reject do |key, _value|
        SENSITIVE_REDIRECT_HEADERS.include?(key.to_s.downcase)
      end
    end

    def check_max_redirects
      return unless request.max_redirects <= 0

      raise exception_with_response
      
    end

    def exception_with_response
      begin
        klass = Exceptions::EXCEPTIONS_MAP.fetch(code)
      rescue KeyError
        raise RequestFailed.new(self, code)
      end

      raise klass.new(self, code)
    end
  end
end
