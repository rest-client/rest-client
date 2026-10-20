# frozen_string_literal: true

require 'tempfile'
require 'cgi'
require 'netrc'
require 'set'
require 'timeout'

begin
  # Use mime/types/columnar if available, for reduced memory usage
  require 'mime/types/columnar'
rescue LoadError
  require 'mime/types'
end

module Contractful
  # This class is used internally by Contractful to send the request, but you can also
  # call it directly if you'd like to use a method not supported by the
  # main API.  For example:
  #
  #   Contractful::Request.execute(:method => :head, :url => 'http://example.com')
  #
  # Mandatory parameters:
  # * :method
  # * :url
  # Optional parameters (have a look at ssl and/or uri for some explanations):
  # * :headers a hash containing the request headers
  # * :cookies may be a Hash{String/Symbol => String} of cookie values, an
  #     Array<HTTP::Cookie>, or an HTTP::CookieJar containing cookies. These
  #     will be added to a cookie jar before the request is sent.
  # * :user and :password for basic auth, will be replaced by a user/password available in the :url
  # * :block_response call the provided block with the HTTPResponse as parameter
  # * :raw_response return a low-level RawResponse instead of a Response
  # * :log Set the log for this request only, overriding Contractful.log, if
  #      any.
  # * :stream_log_percent (Only relevant with :raw_response => true) Customize
  #     the interval at which download progress is logged. Defaults to every
  #     10% complete.
  # * :max_redirects maximum number of redirections (default to 10)
  # * :max_retries number of times to retry the request when a transient
  #     network failure occurs (connection timeouts, broken/reset connections,
  #     EPIPE) or when the response carries a retryable HTTP status (see
  #     :retry_after). Defaults to 0 (disabled). Retries use exponential
  #     backoff (or the server's Retry-After for HTTP statuses).
  # * :retry_interval base delay in seconds between retries (default 0.5).
  #     The delay doubles with each retry: retry_interval, retry_interval * 2,
  #     retry_interval * 4, ...
  # * :retry_after honor Retry-After / classify retryable HTTP statuses
  #     (408, 425, 429, 500, 502, 503, 504 — see
  #     Contractful::Exceptions::RETRIABLE_STATUSES) and retry them like
  #     network failures when :max_retries is positive. Defaults to true.
  #     The delay between attempts honors a server-provided Retry-After
  #     header (delta-seconds or HTTP-date), falling back to exponential
  #     backoff.
  # * :max_retry_after upper bound (seconds) for a Retry-After delay;
  #     larger values fall back to the exponential backoff (default 60).
  # * :retry_jitter randomize retry delays so many concurrent clients do not
  #     retry in lockstep (the thundering-herd problem). false (default)
  #     keeps the plain exponential backoff; :full draws uniformly from
  #     [0, backoff]; :equal from [backoff, 2 * backoff]; :decorrelated
  #     draws from [retry_interval, min(cap, previous * 3)] per the AWS
  #     "Exponential Backoff and Jitter" recipe. Jitter applies only to
  #     exponential backoff — a server-provided Retry-After delay is
  #     honored exactly as sent.
  # * :retry_jitter_cap upper bound (seconds) for the :decorrelated jitter
  #     draw (default 30).
  # * :retry_rng source of randomness for :retry_jitter — any object
  #     responding to #rand(range) (a seeded <tt>Random.new(seed)</tt>
  #     makes tests deterministic). Defaults to the Random class.
  # * :breaker host-level circuit breaker, opt-in. true uses the defaults
  #     ({Contractful::CircuitBreaker::DEFAULT_THRESHOLD} consecutive
  #     failures, then fail fast for
  #     {Contractful::CircuitBreaker::DEFAULT_COOLDOWN} seconds); a Hash
  #     customizes it as <tt>breaker: { threshold: 5, cooldown: 30 }</tt>.
  #     Failures are network errors and retryable statuses (408/425/429/5xx);
  #     a request that ultimately fails after its retries counts once.
  #     While open, requests fail fast with
  #     {Contractful::CircuitOpenError}. State transitions post a `circuit`
  #     notification.
  # * :pace proactive rate-limit enforcement (opt-in). true uses the
  #     defaults ({Contractful::Pacer::DEFAULT_LIMIT} requests per
  #     {Contractful::Pacer::DEFAULT_WINDOW}s per scheme/host/port across
  #     the process); a Hash customizes it:
  #     <tt>pace: { limit: 100, window: 60, max_wait: 10 }</tt>. When the
  #     window is full the request sleeps until a slot frees (posting a
  #     `pace` notification); a wait beyond `max_wait` raises
  #     {Contractful::PacingTimeout}. Retries acquire a slot per attempt.
  # * :proxy An HTTP proxy URI to use for this request. Any value here
  #   (including nil) will override Contractful.proxy.
  # * :persistent reuse the underlying connection across requests via the
  #     process-wide Contractful.connection_pool (HTTP keep-alive). Defaults to
  #     false. See Contractful::ConnectionPool.
  # * :verify_ssl enable ssl verification, possible values are constants from
  #     OpenSSL::SSL::VERIFY_*, defaults to OpenSSL::SSL::VERIFY_PEER
  # * :read_timeout, :write_timeout and :open_timeout are how long to wait
  #     to read from, write to, and open a connection, in seconds. Pass nil to
  #     disable the timeout.
  # * :timeout can be used to set read and open timeouts together
  # * :ssl_client_cert, :ssl_client_key, :ssl_ca_file, :ssl_ca_path,
  #     :ssl_cert_store, :ssl_verify_callback, :ssl_verify_callback_warnings,
  #     :ssl_min_version, :ssl_max_version
  # * :ssl_version specifies the SSL version for the underlying Net::HTTP connection
  # * :ssl_ciphers sets SSL ciphers for the connection. See
  #     OpenSSL::SSL::SSLContext#ciphers=
  # * :before_execution_proc a Proc to call before executing the request. This
  #      proc, like procs from Contractful.before_execution_procs, will be
  #      called with the HTTP request and request params.
  class Request
    attr_reader :method, :uri, :url, :headers, :payload, :proxy,
                :user, :password, :read_timeout, :write_timeout, :max_redirects,
                :open_timeout, :raw_response, :processed_headers, :args,
                :ssl_opts, :max_retries, :retry_interval, :persistent,
                :retry_after, :max_retry_after,
                :retry_jitter, :retry_jitter_cap, :retry_rng,
                :breaker,
                :pace

    # An array of previous redirection responses
    attr_accessor :redirection_history

    def self.execute(args, & block)
      new(args).execute(& block)
    end

    SSL_OPTION_LIST = %w[client_cert client_key ca_file ca_path cert_store
                         version ciphers verify_callback verify_callback_warnings
                         min_version max_version]

    # Maps user-friendly SSL version spellings to the integer constants
    # accepted by OpenSSL::SSL::SSLContext#min_version=/max_version=. Both the
    # "TLSv1_2" and "TLS1_2" spellings are normalized, since the exact symbol
    # format accepted by OpenSSL has varied across OpenSSL gem releases.
    # Integers (e.g. OpenSSL::SSL::TLS1_2_VERSION) and unknown values are
    # passed through unchanged.
    SSL_VERSION_CONSTANTS = {
      'SSLV2' => 'SSL2_VERSION',
      'SSLV3' => 'SSL3_VERSION',
      'SSL2' => 'SSL2_VERSION',
      'SSL3' => 'SSL3_VERSION',
      'TLSV1' => 'TLS1_VERSION',
      'TLSV1_1' => 'TLS1_1_VERSION',
      'TLSV1_2' => 'TLS1_2_VERSION',
      'TLSV1_3' => 'TLS1_3_VERSION',
      'TLS1' => 'TLS1_VERSION',
      'TLS1_1' => 'TLS1_1_VERSION',
      'TLS1_2' => 'TLS1_2_VERSION',
      'TLS1_3' => 'TLS1_3_VERSION'
    }.freeze

    # Request headers whose values are credentials. Their values are redacted
    # from the request log (see docs/security/THREAT_MODEL.md T5 and
    # docs/operations/OBSERVABILITY.md, which promise that auth headers are
    # not logged).
    REDACTED_HEADERS = %w[authorization proxy-authorization cookie].freeze

    # Placeholder written to the log in place of a redacted header value.
    REDACTED_VALUE = '[REDACTED]'

    # Network-level failures that are considered transient. When the
    # `:max_retries` request option is greater than zero, requests that fail
    # with one of these errors are retried automatically (with exponential
    # backoff). Retryable HTTP statuses (`Exceptions::RETRIABLE_STATUSES`)
    # are retried by the pipeline as well; see #execute.
    RETRIABLE_EXCEPTIONS = [
      Contractful::Exceptions::Timeout, # includes Open/Read/WriteTimeout
      Contractful::ServerBrokeConnection,
      Errno::ECONNRESET,
      Errno::ECONNABORTED,
      Errno::EPIPE
    ].freeze

    def inspect
      "<Contractful::Request @method=#{@method.inspect}, @url=#{redacted_url.inspect}>"
    end

    def initialize args
      @method = normalize_method(args[:method])
      @headers = (args[:headers] || {}).dup
      raise ArgumentError, 'must pass :url' unless args[:url]

      @url = process_url_params(normalize_url(args[:url]), headers)
      
        
      

      @user = @password = nil
      parse_url_with_auth!(url)

      # process cookie arguments found in headers or args
      @cookie_jar = process_cookie_args!(@uri, @headers, args)

      @payload = Payload.generate(args[:payload])

      @user = args[:user] if args.include?(:user)
      @password = args[:password] if args.include?(:password)

      if args.include?(:timeout)
        @read_timeout = args[:timeout]
        @open_timeout = args[:timeout]
      end
      @read_timeout = args[:read_timeout] if args.include?(:read_timeout)
      @open_timeout = args[:open_timeout] if args.include?(:open_timeout)
      @write_timeout = args[:write_timeout] if args.include?(:write_timeout)
      @block_response = args[:block_response]
      @raw_response = args[:raw_response] || false
      @persistent = args.fetch(:persistent, false)

      @stream_log_percent = args[:stream_log_percent] || 10
      if @stream_log_percent <= 0 || @stream_log_percent > 100
        raise ArgumentError.new(
          "Invalid :stream_log_percent #{@stream_log_percent.inspect}"
        )
      end

      @proxy = args.fetch(:proxy) if args.include?(:proxy)

      @ssl_opts = {}

      if args.include?(:verify_ssl)
        v_ssl = args.fetch(:verify_ssl)
        @ssl_opts[:verify_ssl] =
          if v_ssl == true
            # interpret :verify_ssl => true as VERIFY_PEER
            OpenSSL::SSL::VERIFY_PEER
          elsif v_ssl
            # otherwise pass through any truthy values
            v_ssl
          else
            # interpret all falsy :verify_ssl values as VERIFY_NONE
            OpenSSL::SSL::VERIFY_NONE
          end
      else
        # if :verify_ssl was not passed, default to VERIFY_PEER
        @ssl_opts[:verify_ssl] = OpenSSL::SSL::VERIFY_PEER
      end

      SSL_OPTION_LIST.each do |key|
        source_key = ('ssl_' + key).to_sym
        @ssl_opts[key.to_sym] = args.fetch(source_key) if args.has_key?(source_key)
      end

      # Set some other default SSL options, but only if we have an HTTPS URI.
      # If there's no CA file, CA path, or cert store provided, use default
      if use_ssl? && !ssl_ca_file && !ssl_ca_path && !@ssl_opts.include?(:cert_store)
        @ssl_opts[:cert_store] = self.class.default_ssl_cert_store
      end

      @log = args[:log]
      @max_redirects = args[:max_redirects] || 10

      @max_retries = args.fetch(:max_retries, 0)
      unless @max_retries.is_a?(Integer) && @max_retries >= 0
        raise ArgumentError.new(
          ':max_retries must be a non-negative Integer, ' +
          "got #{@max_retries.inspect}"
        )
      end

      @retry_interval = args.fetch(:retry_interval, 0.5)
      unless @retry_interval.is_a?(Numeric) && @retry_interval >= 0
        raise ArgumentError.new(
          ':retry_interval must be a non-negative Numeric, ' +
          "got #{@retry_interval.inspect}"
        )
      end

      @retry_jitter = args.fetch(:retry_jitter, false)
      unless [false, :full, :equal, :decorrelated].include?(@retry_jitter)
        raise ArgumentError.new(
          ':retry_jitter must be false, :full, :equal or :decorrelated, ' +
          "got #{@retry_jitter.inspect}"
        )
      end

      @retry_jitter_cap = args.fetch(:retry_jitter_cap, 30.0)
      unless @retry_jitter_cap.is_a?(Numeric) && @retry_jitter_cap.positive?
        raise ArgumentError.new(
          ':retry_jitter_cap must be a positive Numeric, ' +
          "got #{@retry_jitter_cap.inspect}"
        )
      end

      @retry_rng = args.fetch(:retry_rng, Random)
      unless @retry_rng.respond_to?(:rand)
        raise ArgumentError.new(
          ':retry_rng must respond to #rand(range), ' +
          "got #{@retry_rng.inspect}"
        )
      end

      @breaker = args.fetch(:breaker, false)
      case @breaker
      when false, true, Hash
        # ok
      else
        raise ArgumentError.new(
          ':breaker must be true, false or a config Hash, ' +
          "got #{@breaker.inspect}"
        )
      end

      @pace = args.fetch(:pace, false)
      case @pace
      when false, true, Hash
        # ok
      else
        raise ArgumentError.new(
          ':pace must be true, false or a config Hash, ' +
          "got #{@pace.inspect}"
        )
      end

      @retry_after = args.fetch(:retry_after, true) ? true : false
      @max_retry_after = args.fetch(:max_retry_after, 60)
      unless @max_retry_after.is_a?(Numeric) && @max_retry_after >= 0
        raise ArgumentError.new(
          ':max_retry_after must be a non-negative Numeric, ' +
          "got #{@max_retry_after.inspect}"
        )
      end

      @processed_headers = make_headers headers
      @processed_headers_lowercase = @processed_headers.map do |k, v|
        [k.downcase, v]
      end.to_h
      @args = args

      @before_execution_proc = args[:before_execution_proc]
    end

    def execute & block
      # With 2.0.0+, net/http accepts URI objects in requests and handles wrapping
      # IPv6 addresses in [] for use in the Host request header.
      #
      # The request is rebuilt on each attempt so that Net::HTTP mutations (for
      # example basic auth headers) and consumed payload streams do not leak
      # state between attempts.
      attempts = 0
      started = nil
      event_url = redacted_url
      response_for_attempt = nil
      attempt_block =
        if block
          proc do |http_response, request, raw|
            response_for_attempt = http_response
            block.call(http_response, request, raw, &block)
          end
        end
      breaker = @breaker ? CircuitBreaker.registry.breaker_for(uri, **breaker_options) : nil
      breaker&.check!
      pacer = @pace ? Pacer.registry.pacer_for(uri, **pace_options) : nil
      begin
        loop do
          req = net_http_request_class(method).new(uri, processed_headers)
          pacer&.acquire
          Notifications.post('request', method: method, url: event_url, attempt: attempts + 1)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          response_for_attempt = nil
          result = transmit uri, req, payload, & attempt_block
          response = result.is_a?(Contractful::Response) ? result : response_for_attempt
          Notifications.post(
            'response', method: method, url: event_url,
                        status: response.respond_to?(:code) ? response.code : nil,
                        duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
          )

          # When a block handles responses itself (error-status suppression),
          # retryable statuses never raise — judge the returned response.
          if block_given? && retry_after && attempts < max_retries &&
             response.is_a?(Contractful::Response) &&
             Exceptions.retryable?(response.code) && rewind_payload!
            attempts += 1
            delay = retry_delay_for_response(response, attempts)
            Notifications.post('retry', method: method, url: event_url,
                                        attempt: attempts, delay: delay, cause: response.code)
            log_response_retry(response, attempts, delay)
            sleep_for_retry(delay)
            next
          end
          breaker&.record_response(response)
          break result
        end
      rescue *RETRIABLE_EXCEPTIONS => e
        attempts += 1
        if attempts <= max_retries && rewind_payload!
          delay = retry_backoff_delay(attempts)
          Notifications.post('retry', method: method, url: event_url,
                                      attempt: attempts, delay: delay, cause: e.class.name)
          log_retry(e, attempts, delay)
          sleep_for_retry(delay)
          retry
        end
        breaker&.record_failure
        raise
      rescue Contractful::ExceptionWithResponse => e
        # Error statuses raise inside transmit, so the response event for a
        # failed attempt posts here rather than after the transmit call.
        Notifications.post(
          'response', method: method, url: event_url, status: e.http_code,
                      duration_ms: started && ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
        )
        attempts += 1
        if retry_after && attempts <= max_retries && e.retryable? && rewind_payload!
          delay = retry_delay_for_response(e.response, attempts)
          Notifications.post('retry', method: method, url: event_url, attempt: attempts,
                                      delay: delay,
                                      cause: e.response ? e.http_code : e.class.name)
          log_retry(e, attempts, delay)
          sleep_for_retry(delay)
          retry
        end
        breaker&.record_response(e.response) if e.response
        breaker&.record_failure unless e.response
        raise
      end
    ensure
      payload&.close
    end

    # Exceptions that are retried automatically when `:max_retries` is used.
    def self.retriable_exceptions
      RETRIABLE_EXCEPTIONS
    end

    # SSL-related options
    def verify_ssl
      @ssl_opts.fetch(:verify_ssl)
    end
    SSL_OPTION_LIST.each do |key|
      define_method('ssl_' + key) do
        @ssl_opts[key.to_sym]
      end
    end

    # Return true if the request URI will use HTTPS.
    #
    # @return [Boolean]
    #
    def use_ssl?
      uri.is_a?(URI::HTTPS)
    end

    # Extract the query parameters and append them to the url
    #
    # Look through the headers hash for a :params option (case-insensitive,
    # may be string or symbol). If present and the value is a Hash or
    # Contractful::ParamsArray, *delete* the key/value pair from the headers
    # hash and encode the value into a query string. Append this query string
    # to the URL and return the resulting URL.
    #
    # @param [String] url
    # @param [Hash] headers An options/headers hash to process. Mutation
    #   warning: the params key may be removed if present!
    #
    # @return [String] resulting url with query string
    #
    def process_url_params(url, headers)
      url_params = nil

      # find and extract/remove "params" key if the value is a Hash/ParamsArray
      headers.delete_if do |key, value|
        if key.to_s.downcase == 'params' &&
           (value.is_a?(Hash) || value.is_a?(Contractful::ParamsArray))
          raise ArgumentError.new("Multiple 'params' options passed") if url_params

          url_params = value
          true
        else
          false
        end
      end

      # build resulting URL with query string
      if url_params && !url_params.empty?
        query_string = Contractful::Utils.encode_query_string(url_params)

        if url.include?('?')
          url + '&' + query_string
        else
          url + '?' + query_string
        end
      else
        url
      end
    end

    # Render a hash of key => value pairs for cookies in the Request#cookie_jar
    # that are valid for the Request#uri. This will not necessarily include all
    # cookies if there are duplicate keys. It's safer to use the cookie_jar
    # directly if that's a concern.
    #
    # @see Request#cookie_jar
    #
    # @return [Hash]
    #
    def cookies
      hash = {}

      @cookie_jar.cookies(uri).each do |c|
        hash[c.name] = c.value
      end

      hash
    end

    # @return [HTTP::CookieJar]
    attr_reader :cookie_jar

    # Render a Cookie HTTP request header from the contents of the @cookie_jar,
    # or nil if the jar is empty.
    #
    # @see Request#cookie_jar
    #
    # @return [String, nil]
    #
    def make_cookie_header
      return nil if cookie_jar.nil?

      arr = cookie_jar.cookies(url)
      return nil if arr.empty?

      HTTP::Cookie.cookie_value(arr)
    end

    # Process cookies passed as hash or as HTTP::CookieJar. For backwards
    # compatibility, these may be passed as a :cookies option masquerading
    # inside the headers hash. To avoid confusion, if :cookies is passed in
    # both headers and Request#initialize, raise an error.
    #
    # :cookies may be a:
    # - Hash{String/Symbol => String}
    # - Array<HTTP::Cookie>
    # - HTTP::CookieJar
    #
    # Passing as a hash:
    #   Keys may be symbols or strings. Values must be strings.
    #   Infer the domain name from the request URI and allow subdomains (as
    #   though '.example.com' had been set in a Set-Cookie header). Assume a
    #   path of '/'.
    #
    #     Contractful::Request.new(url: 'http://example.com', method: :get,
    #       :cookies => {:foo => 'Value', 'bar' => '123'}
    #     )
    #
    # results in cookies as though set from the server by:
    #     Set-Cookie: foo=Value; Domain=.example.com; Path=/
    #     Set-Cookie: bar=123; Domain=.example.com; Path=/
    #
    # which yields a client cookie header of:
    #     Cookie: foo=Value; bar=123
    #
    # Passing as HTTP::CookieJar, which will be passed through directly:
    #
    #     jar = HTTP::CookieJar.new
    #     jar.add(HTTP::Cookie.new('foo', 'Value', domain: 'example.com',
    #                              path: '/', for_domain: false))
    #
    #     Contractful::Request.new(..., :cookies => jar)
    #
    # @param [URI::HTTP] uri The URI for the request. This will be used to
    # infer the domain name for cookies passed as strings in a hash. To avoid
    # this implicit behavior, pass a full cookie jar or use HTTP::Cookie hash
    # values.
    # @param [Hash] headers The headers hash from which to pull the :cookies
    #   option. MUTATION NOTE: This key will be deleted from the hash if
    #   present.
    # @param [Hash] args The options passed to Request#initialize. This hash
    #   will be used as another potential source for the :cookies key.
    #   These args will not be mutated.
    #
    # @return [HTTP::CookieJar] A cookie jar containing the parsed cookies.
    #
    def process_cookie_args!(uri, headers, args)
      # Avoid ambiguity in whether options from headers or options from
      # Request#initialize should take precedence by raising ArgumentError when
      # both are present. Prior versions of contractful claimed to give
      # precedence to init options, but actually gave precedence to headers.
      # Avoid that mess by erroring out instead.
      if headers[:cookies] && args[:cookies]
        raise ArgumentError.new(
          'Cannot pass :cookies in Request.new() and in headers hash'
        )
      end

      cookies_data = headers.delete(:cookies) || args[:cookies]

      # return copy of cookie jar as is
      return cookies_data.dup if cookies_data.is_a?(HTTP::CookieJar)

      # convert cookies hash into a CookieJar
      jar = HTTP::CookieJar.new

      (cookies_data || []).each do |key, val|
        # Support for Array<HTTP::Cookie> mode:
        # If key is a cookie object, add it to the jar directly and assert that
        # there is no separate val.
        if key.is_a?(HTTP::Cookie)
          raise ArgumentError.new("extra cookie val: #{val.inspect}") if val

          jar.add(key)
          next
        end

        key = key.to_s if key.is_a?(Symbol)

        # assume implicit domain from the request URI, and set for_domain to
        # permit subdomains
        jar.add(HTTP::Cookie.new(key, val, domain: uri.hostname.downcase,
                                           path: '/', for_domain: true))
      end

      jar
    end

    # Generate headers for use by a request. Header keys will be stringified
    # using `#stringify_headers` to normalize them as capitalized strings.
    #
    # The final headers consist of:
    #   - default headers from #default_headers
    #   - user_headers provided here
    #   - headers from the payload object (e.g. Content-Type, Content-Lenth)
    #   - cookie headers from #make_cookie_header
    #
    # stringify_headers only normalizes Symbol keys to the canonical
    # `Content-Type` style capitalization; String keys are passed through
    # verbatim for backwards compatibility with rest-client 1.x/2.x
    # (https://github.com/rest-client/rest-client/issues/599). Because
    # equivalent header names may therefore be spelled with different
    # casing, the merges below are case-insensitive: a later header whose
    # name matches an earlier one case-insensitively replaces it (keeping
    # the casing of the later name) instead of coexisting with it. This both
    # keeps the accidental-override warnings working across casings and
    # prevents duplicate headers from reaching the wire.
    #
    # @param [Hash] user_headers User-provided headers to include
    #
    # @return [Hash<String, String>] A hash of HTTP headers => values
    #
    def make_headers(user_headers)
      headers = merge_headers(stringify_headers(default_headers),
                              stringify_headers(user_headers))

      # override headers from the payload (e.g. Content-Type, Content-Length)
      if @payload
        payload_headers = @payload.headers

        # Warn the user if we override any headers that were previously
        # present. This usually indicates that contractful was passed
        # conflicting information, e.g. if it was asked to render a payload as
        # x-www-form-urlencoded but a Content-Type application/json was
        # also supplied by the user.
        payload_headers.each_pair do |key, val|
          next unless (existing = header_key_for(headers, key)) && headers[existing] != val

          warn("warning: Overriding #{key.inspect} header " +
               "#{headers[existing].inspect} with #{val.inspect} " +
               'due to payload')
        end

        headers = merge_headers(headers, payload_headers)
      end

      # merge in cookies
      cookies = make_cookie_header
      if cookies && !cookies.empty?
        warn('warning: overriding "Cookie" header with :cookies option') if header_key_for(headers, 'Cookie')
        headers = merge_headers(headers, { 'Cookie' => cookies })
      end

      headers
    end

    # The proxy URI for this request. If `:proxy` was provided on this request,
    # use it over `Contractful.proxy`.
    #
    # Return false if a proxy was explicitly set and is falsy.
    #
    # @return [URI, false, nil]
    #
    def proxy_uri
      if defined?(@proxy)
        if @proxy
          URI.parse(@proxy)
        else
          false
        end
      elsif Contractful.proxy_set?
        if Contractful.proxy
          URI.parse(Contractful.proxy)
        else
          false
        end
      end
    end

    def net_http_object(hostname, port)
      p_uri = proxy_uri

      if p_uri.nil?
        # no proxy set
        Net::HTTP.new(hostname, port)
      elsif !p_uri
        # proxy explicitly set to none
        Net::HTTP.new(hostname, port, nil, nil, nil, nil)
      else
        Net::HTTP.new(hostname, port,
                      p_uri.hostname, p_uri.port, p_uri.user, p_uri.password)

      end
    end

    def net_http_request_class(method)
      Net::HTTP.const_get(method.capitalize, false)
    end

    def net_http_do_request(http, req, body = nil, &block)
      return http.request(req, body, &block) unless body&.respond_to?(:read)

      req.body_stream = body
      http.request(req, nil, &block)
      
        
      
    end

    # Normalize a URL by adding a protocol if none is present.
    #
    # If the string has no HTTP-like scheme (i.e. scheme followed by '//'), a
    # scheme of 'http' will be added. This mimics the behavior of browsers and
    # user agents like cURL.
    #
    # @param [String] url A URL string.
    #
    # @return [String]
    #
    def normalize_url(url)
      url = 'http://' + url unless url.match(%r{\A[a-z][a-z0-9+.-]*://}i)
      url
    end

    # Return a certificate store that can be used to validate certificates with
    # the system certificate authorities. This will probably not do anything on
    # OS X, which monkey patches OpenSSL in terrible ways to insert its own
    # validation. On most *nix platforms, this will add the system certifcates
    # using OpenSSL::X509::Store#set_default_paths. On Windows, this will use
    # Contractful::Windows::RootCerts to look up the CAs trusted by the system.
    #
    # @return [OpenSSL::X509::Store]
    #
    def self.default_ssl_cert_store
      cert_store = OpenSSL::X509::Store.new
      cert_store.set_default_paths

      # set_default_paths() doesn't do anything on Windows, so look up
      # certificates using the win32 API.
      if Contractful::Platform.windows?
        Contractful::Windows::RootCerts.instance.to_a.uniq.each do |cert|
          
          cert_store.add_cert(cert)
        rescue OpenSSL::X509::StoreError => e
          # ignore duplicate certs
          raise unless e.message == 'cert already in hash table'
          
        end
      end

      cert_store
    end

    def redacted_uri
      return unless uri

      if uri.password
        sanitized_uri = uri.dup
        sanitized_uri.password = 'REDACTED'
        sanitized_uri
      else
        uri
      end
    end

    def redacted_url
      redacted_uri.to_s
    end

    # Default to the global logger if there's not a request-specific one
    def log
      @log || Contractful.log
    end

    def log_request
      return unless log

      out = []

      out << "Contractful.#{method} #{redacted_url.inspect}"
      out << payload.short_inspect if payload
      out << processed_headers.to_a.sort.map { |(k, v)|
        [k.inspect, log_header_value(k, v).inspect].join('=>')
      }.join(', ')
      log << (out.join(', ') + "\n")
    end

    # Value to render for a header in the request log. Credential-bearing
    # headers (Authorization, Proxy-Authorization, Cookie) are redacted so
    # that enabling logging cannot leak tokens or session cookies.
    def log_header_value(key, value)
      if REDACTED_HEADERS.include?(key.to_s.downcase)
        REDACTED_VALUE
      else
        value
      end
    end
    private :log_header_value

    # Return a hash of headers whose keys are capitalized strings
    #
    # Design note: only Symbol keys are normalized to `Content-Type` style
    # capitalization. String keys are passed through verbatim, matching
    # rest-client 1.x/2.x behavior
    # (https://github.com/rest-client/rest-client/issues/599). String keys
    # are therefore not canonicalized (e.g. 'x-custom-header' stays
    # lowercase on the wire), which some clients depend on; equivalent
    # header names that differ in casing are treated as the same header at
    # merge time by #make_headers/#merge_headers.
    #
    def stringify_headers headers
      headers.each_with_object({}) do |(key, value), result|
        key = key.to_s.split('_').map(&:capitalize).join('-') if key.is_a? Symbol
        if 'CONTENT-TYPE' == key.upcase
          result[key] = maybe_convert_extension(value.to_s)
        elsif 'ACCEPT' == key.upcase
          # Accept can be composed of several comma-separated values
          if value.is_a? Array
            target_values = value
          else
            target_values = value.to_s.split ','
          end
          result[key] = target_values.map do |ext|
            maybe_convert_extension(ext.to_s.strip)
          end.join(', ')
        else
          result[key] = value.to_s
        end
      end
    end

    # Return the key in `headers` that equals `key` case-insensitively, or
    # nil if there is no match. HTTP header names are case-insensitive
    # (RFC 7230), and because stringify_headers passes String keys through
    # verbatim, equivalent names may be spelled with different casing.
    #
    # @return [String, nil] the matching key as present in `headers`
    #
    def header_key_for(headers, key)
      headers.each_key do |existing|
        return existing if existing.casecmp?(key)
      end
      nil
    end
    private :header_key_for

    # Merge two header hashes, treating keys that differ only in case as the
    # same header: entries from `later` replace entries from `earlier`,
    # keeping the casing of the later key. This prevents, for example, a
    # user-supplied 'content-type' from coexisting with the default
    # 'Accept'-style capitalized headers and producing a duplicate header on
    # the wire.
    #
    # @param [Hash] earlier headers merged in first
    # @param [Hash] later headers that win on (case-insensitive) collision
    #
    # @return [Hash]
    #
    def merge_headers(earlier, later)
      merged = earlier.dup
      later.each do |key, val|
        if (existing = header_key_for(merged, key)) && !existing.eql?(key)
          merged.delete(existing)
        end
        merged[key] = val
      end
      merged
    end
    private :merge_headers

    # Default headers set by Contractful. In addition to these headers, servers
    # will receive headers set by Net::HTTP, such as Accept-Encoding and Host.
    #
    # @return [Hash<Symbol, String>]
    def default_headers
      {
        accept: '*/*',
        user_agent: Contractful::Platform.default_user_agent
      }
    end

    private

    # Rewind the payload so that a retried request can send the body again.
    # Returns true when there is no payload or it was successfully rewound,
    # false when the payload cannot be rewound (e.g. a non-rewindable request
    # stream), in which case retrying would resend a truncated or empty body.
    def rewind_payload!
      return true unless payload

      payload.rewind
    end

    # Exponential backoff between retries: `:retry_interval` for the first
    # retry, then doubling for each subsequent attempt.
    def retry_backoff_delay(attempt)
      delay = retry_interval * (2**(attempt - 1))
      apply_retry_jitter(delay, attempt)
    end

    # Randomize an exponential backoff per the configured jitter style.
    # Called only for computed backoff — a server's Retry-After delay is
    # honored exactly, so many clients still retry in unison only when the
    # server itself asked them to.
    def apply_retry_jitter(delay, attempt)
      return delay if @retry_jitter == false || delay.zero?

      case @retry_jitter
      when :full then @retry_rng.rand(0..delay)
      when :equal then delay + @retry_rng.rand(0..delay)
      when :decorrelated then decorrelated_jitter_delay(attempt)
      end
    end

    # Normalize the :pace option into registry kwargs.
    def pace_options
      case @pace
      when Hash
        { limit: @pace.fetch(:limit, Pacer::DEFAULT_LIMIT),
          window: @pace.fetch(:window, Pacer::DEFAULT_WINDOW),
          max_wait: @pace.fetch(:max_wait, Pacer::DEFAULT_MAX_WAIT) }
      else
        { limit: Pacer::DEFAULT_LIMIT, window: Pacer::DEFAULT_WINDOW,
          max_wait: Pacer::DEFAULT_MAX_WAIT }
      end
    end

    # Normalize the :breaker option into registry kwargs.
    def breaker_options
      case @breaker
      when Hash
        { threshold: @breaker.fetch(:threshold, CircuitBreaker::DEFAULT_THRESHOLD),
          cooldown: @breaker.fetch(:cooldown, CircuitBreaker::DEFAULT_COOLDOWN) }
      else
        { threshold: CircuitBreaker::DEFAULT_THRESHOLD,
          cooldown: CircuitBreaker::DEFAULT_COOLDOWN }
      end
    end

    # AWS "Exponential Backoff and Jitter" decorrelated draw: each attempt
    # samples [retry_interval, min(cap, previous * 3)], where the previous
    # value is the raw (unjittered) backoff of the preceding attempt —
    # stateless per request, deterministic under a seeded :retry_rng.
    def decorrelated_jitter_delay(attempt)
      base = retry_interval
      previous = attempt <= 1 ? base : base * (2**(attempt - 2))
      draw = @retry_rng.rand(base..[previous * 3, @retry_jitter_cap].min)
      [draw, @retry_jitter_cap].min
    end

    def sleep_for_retry(secs)
      sleep(secs) if secs.positive?
    end

    # Delay before retrying after a retryable HTTP response: honor the
    # server's Retry-After header (seconds or HTTP-date) when present and
    # within :max_retry_after; on a 429 without Retry-After, fall back to
    # the RateLimit-Reset quota window; otherwise exponential backoff.
    def retry_delay_for_response(response, attempt)
      header = response.headers[:retry_after] if response.respond_to?(:headers)
      delay = parse_retry_after(header)

      if delay.nil? && response.respond_to?(:rate_limit) && response.code == 429
        delay = rate_limit_reset_delay(response)
      end

      if delay.nil? || delay > max_retry_after
        retry_backoff_delay(attempt)
      else
        delay
      end
    end

    # Seconds until the reported rate-limit quota resets, when the server
    # sent RateLimit-Reset (or the legacy X-RateLimit-Reset).
    def rate_limit_reset_delay(response)
      info = response.rate_limit
      return nil unless info&.reset

      secs = info.reset_in
      secs&.positive? ? secs : nil
    end

    # Retry-After: delta-seconds ("120") or HTTP-date ("Wed, 21 Oct 2026 07:28:00 GMT").
    def parse_retry_after(value)
      return nil if value.nil?

      if value.match?(/\A\d+\z/)
        value.to_f
      else
        require 'time'
        delay = Time.httpdate(value) - Time.now
        delay.positive? ? delay : 0.0
      end
    rescue StandardError
      nil
    end

    def log_response_retry(response, attempt, delay)
      return unless log

      log << ("Contractful retry ##{attempt}/#{max_retries} for " +
             "#{redacted_url.inspect} after response HTTP #{response.code}: " +
             "sleeping #{delay}s\n")
    end

    def log_retry(err, attempt, delay)
      return unless log

      log << ("Contractful retry ##{attempt}/#{max_retries} for " +
             "#{redacted_url.inspect} after #{err.class}: " +
             "sleeping #{delay}s\n")
    end

    # Parse the `@url` string into a URI object and save it as
    # `@uri`. Also save any basic auth user or password as @user and @password.
    # If no auth info was passed, check for credentials in a Netrc file.
    #
    # @param [String] url A URL string.
    #
    # @return [URI]
    #
    # @raise URI::InvalidURIError on invalid URIs
    #
    def parse_url_with_auth!(url)
      uri = URI.parse(url)

      # Ruby >= 3.4 returns an empty hostname (rather than nil) for URIs
      # such as 'http:///'.
      raise URI::InvalidURIError.new("bad URI(no host provided): #{url}") if uri.hostname.nil? || uri.hostname.empty?

      @user = CGI.unescape(uri.user) if uri.user
      @password = CGI.unescape(uri.password) if uri.password
      @user, @password = Netrc.read[uri.hostname] if !@user && !@password

      @uri = uri
    end

    def print_verify_callback_warnings
      warned = false
      if Contractful::Platform.mac_mri?
        warn('warning: ssl_verify_callback return code is ignored on OS X')
        warned = true
      end
      if Contractful::Platform.jruby?
        warn('warning: SSL verify_callback may not work correctly in jruby')
        warn('see https://github.com/jruby/jruby/issues/597')
        warned = true
      end
      warned
    end

    # Parse a method and return a normalized string version.
    #
    # Raise ArgumentError if the method is falsy, but otherwise do no
    # validation.
    #
    # @param method [String, Symbol]
    #
    # @return [String]
    #
    # @see net_http_request_class
    #
    def normalize_method(method)
      raise ArgumentError.new('must pass :method') unless method

      method.to_s.downcase
    end

    def transmit uri, req, payload, & block
      # We set this to true in the net/http block so that we can distinguish
      # read_timeout from open_timeout. Now that we only support Ruby 2.0+,
      # this is only needed for Timeout exceptions thrown outside of Net::HTTP.
      established_connection = false

      setup_credentials req

      net = net_http_object(uri.hostname, uri.port)
      configure_net_http(net, uri)

      Contractful.before_execution_procs.each do |before_proc|
        before_proc.call(req, args)
      end

      @before_execution_proc.call(req, args) if @before_execution_proc

      log_request

      start_time = Time.now
      tempfile = nil

      if persistent
        pool = Contractful.connection_pool
        key = persistent_connection_key(uri)

        http = pool.checkout(key) { net.start }
        # The pooled connection may have been built by a request with different
        # timeout settings; always (re)apply this request's timeouts.
        apply_timeouts!(http)

        begin
          established_connection = true
          res, tempfile = perform_net_http_request(http, req, payload)
        rescue ::Exception
          # The connection state cannot be trusted after any failure; never
          # return it to the pool.
          pool.invalidate(key, http)
          raise
        end

        pool.checkin(key, http)

        # Process the result only after the connection has been returned to
        # the pool: process_result may raise for HTTP error responses, and
        # those leave the connection perfectly reusable.
        process_result(res, start_time, tempfile, &block) unless @block_response
      else
        net.start do |http|
          established_connection = true

          res, tempfile = perform_net_http_request(http, req, payload)
          process_result(res, start_time, tempfile, &block) unless @block_response
        end
      end
    rescue EOFError
      raise Contractful::ServerBrokeConnection
    rescue Net::OpenTimeout => e
      raise Contractful::Exceptions::OpenTimeout.new(nil, e)
    rescue Net::ReadTimeout => e
      raise Contractful::Exceptions::ReadTimeout.new(nil, e)
    rescue Net::WriteTimeout => e
      raise Contractful::Exceptions::WriteTimeout.new(nil, e)
    rescue Timeout::Error, Errno::ETIMEDOUT => e
      # handling for non-Net::HTTP timeouts
      raise Contractful::Exceptions::ReadTimeout.new(nil, e) if established_connection
        
      
      raise Contractful::Exceptions::OpenTimeout.new(nil, e)
      
    rescue OpenSSL::SSL::SSLError => e
      # TODO: deprecate and remove Contractful::SSLCertificateNotVerified and just
      # pass through OpenSSL::SSL::SSLError directly.
      #
      # Exceptions in verify_callback are ignored [1], and jruby doesn't support
      # it at all [2]. Contractful has to catch OpenSSL::SSL::SSLError and either
      # re-throw it as is, or throw SSLCertificateNotVerified based on the
      # contents of the message field of the original exception.
      #
      # The client has to handle OpenSSL::SSL::SSLError exceptions anyway, so
      # we shouldn't make them handle both OpenSSL and Contractful exceptions.
      #
      # [1] https://github.com/ruby/ruby/blob/89e70fe8e7/ext/openssl/ossl.c#L238
      # [2] https://github.com/jruby/jruby/issues/597

      raise SSLCertificateNotVerified.new(e.message) if e.message.include?('certificate verify failed')
        
      
      raise e
      
    end

    # Apply the request's SSL settings and timeouts to a Net::HTTP object.
    def configure_net_http(net, uri)
      net.use_ssl = uri.is_a?(URI::HTTPS)
      net.ssl_version = ssl_version if ssl_version
      net.min_version = normalize_ssl_version(ssl_min_version) if ssl_min_version
      net.max_version = normalize_ssl_version(ssl_max_version) if ssl_max_version
      net.ciphers = ssl_ciphers if ssl_ciphers

      net.verify_mode = verify_ssl

      net.cert = ssl_client_cert if ssl_client_cert
      net.key = ssl_client_key if ssl_client_key
      net.ca_file = ssl_ca_file if ssl_ca_file
      net.ca_path = ssl_ca_path if ssl_ca_path
      net.cert_store = ssl_cert_store if ssl_cert_store

      # We no longer rely on net.verify_callback for the main SSL verification
      # because it's not well supported on all platforms (see comments below).
      # But do allow users to set one if they want.
      if ssl_verify_callback
        net.verify_callback = ssl_verify_callback

        # Hilariously, jruby only calls the callback when cert_store is set to
        # something, so make sure to set one.
        # https://github.com/jruby/jruby/issues/597
        net.cert_store ||= OpenSSL::X509::Store.new if Contractful::Platform.jruby?

        if (ssl_verify_callback_warnings != false) && print_verify_callback_warnings
          warn('pass :ssl_verify_callback_warnings => false to silence this')
        end
      end

      if OpenSSL::SSL::VERIFY_PEER == OpenSSL::SSL::VERIFY_NONE
        warn('WARNING: OpenSSL::SSL::VERIFY_PEER == OpenSSL::SSL::VERIFY_NONE')
        warn('This dangerous monkey patch leaves you open to MITM attacks!')
        warn('Try passing :verify_ssl => false instead.')
      end

      apply_timeouts!(net)
    end

    # Apply the request's timeout settings to a Net::HTTP object. Safe to call
    # multiple times and on already-started connections, which is how pooled
    # connections pick up the timeouts of each request that reuses them.
    def apply_timeouts!(net)
      if defined? @read_timeout
        @read_timeout = normalize_timeout_value!(@read_timeout)
        net.read_timeout = @read_timeout
      end
      if defined? @open_timeout
        @open_timeout = normalize_timeout_value!(@open_timeout)
        net.open_timeout = @open_timeout
      end
      return unless defined? @write_timeout

      @write_timeout = normalize_timeout_value!(@write_timeout)
      net.write_timeout = @write_timeout
      
    end

    def normalize_timeout_value!(value)
      if value == -1
        warn 'Deprecated: to disable timeouts, please use nil instead of -1'
        nil
      else
        value
      end
    end

    # Issue the request on a started Net::HTTP connection and read the
    # response body. Returns a [response, tempfile] pair; response is nil when
    # a :block_response was provided, since the block then handles the raw
    # Net::HTTPResponse itself.
    def perform_net_http_request(http, req, payload)
      tempfile = nil

      if @block_response
        net_http_do_request(http, req, payload, &@block_response)
        [nil, nil]
      else
        res = net_http_do_request(http, req, payload) do |http_response|
          if @raw_response
            # fetch body into tempfile
            tempfile = fetch_body_to_tempfile(http_response)
          else
            # fetch body
            http_response.read_body
          end
          http_response
        end
        [res, tempfile]
      end
    end

    # Build the connection pool key for a persistent request. Connections are
    # pooled per scheme/host/port plus proxy and the SSL settings that cannot
    # be changed on a live connection. A custom :ssl_cert_store is assumed to
    # be equivalent for a given host (a fresh default cert store object is
    # built for every request, so object identity cannot be part of the key).
    def persistent_connection_key(uri)
      proxy_part = proxy_uri ? proxy_uri.to_s : 'direct'
      cert_fingerprint = (OpenSSL::Digest::SHA256.hexdigest(ssl_client_cert.to_der) if ssl_client_cert)

      [
        uri.scheme, uri.host, uri.port, proxy_part, verify_ssl,
        ssl_version, ssl_min_version, ssl_max_version, ssl_ciphers,
        ssl_ca_file, ssl_ca_path, cert_fingerprint,
        ssl_verify_callback&.object_id
      ].join('|')
    end

    def setup_credentials(req)
      return unless user && !@processed_headers_lowercase.include?('authorization')

      req.basic_auth(user, password)
      
    end

    def fetch_body_to_tempfile(http_response)
      # Taken from Chef, which as in turn...
      # Stolen from http://www.ruby-forum.com/topic/166423
      # Kudos to _why!
      tf = Tempfile.new('contractful.')
      tf.binmode

      size = 0
      total = http_response['Content-Length'].to_i
      stream_log_bucket = nil

      http_response.read_body do |chunk|
        tf.write chunk
        size += chunk.size
        if log
          # Use the redacted URL here as everywhere else in the log: a URL
          # with embedded basic-auth credentials must not leak into the
          # streaming progress lines.
          if total == 0
            log << format("streaming %s %s (%d of unknown) [0 Content-Length]\n", @method.upcase, redacted_url, size)
          else
            percent = (size * 100) / total
            current_log_bucket, = percent.divmod(@stream_log_percent)
            if current_log_bucket != stream_log_bucket
              stream_log_bucket = current_log_bucket
              log << format("streaming %s %s %d%% done (%d of %d)\n", @method.upcase, redacted_url, (size * 100) / total, size, total)
            end
          end
        end
      end
      tf.close
      tf
    end

    # @param res The Net::HTTP response object
    # @param start_time [Time] Time of request start
    def process_result(res, start_time, tempfile = nil, &block)
      if @raw_response
        raise ArgumentError.new('tempfile is required') unless tempfile

        response = RawResponse.new(tempfile, res, self, start_time)
      else
        response = Response.create(res.body, res, self, start_time)
      end

      response.log_response

      # Public API (frozen since rest-client 1.x, see docs/adr/0004): the
      # user block receives the Response (a String subclass), this request,
      # and the raw Net::HTTP result; the block itself is passed through as
      # a fourth argument for callers that delegate. Do not change the
      # arity or the Response inheritance without a major-version plan.
      if block_given?
        block.call(response, self, res, & block)
      else
        response.return!(&block)
      end
    end

    def parser
      URI.const_defined?(:Parser) ? URI::Parser.new : URI
    end

    # Normalize an SSL version value into the form accepted by
    # OpenSSL::SSL::SSLContext#min_version=/max_version=. Symbols and strings
    # such as :TLSv1_2 or 'TLS1.3' are converted to the corresponding integer
    # protocol version constant when it is available; anything else (integers,
    # :SSLv23, unknown values) is passed through untouched so that OpenSSL can
    # apply its own validation.
    def normalize_ssl_version(value)
      return value unless value.is_a?(Symbol) || value.is_a?(String)

      const_name = SSL_VERSION_CONSTANTS[value.to_s.upcase.tr('.', '_')]
      if const_name && OpenSSL::SSL.const_defined?(const_name)
        OpenSSL::SSL.const_get(const_name)
      else
        value
      end
    end

    # Given a MIME type or file extension, return either a MIME type or, if
    # none is found, the input unchanged.
    #
    #     >> maybe_convert_extension('json')
    #     => 'application/json'
    #
    #     >> maybe_convert_extension('unknown')
    #     => 'unknown'
    #
    #     >> maybe_convert_extension('application/xml')
    #     => 'application/xml'
    #
    # @param ext [String]
    #
    # @return [String]
    #
    def maybe_convert_extension(ext)
      unless ext =~ /\A[a-zA-Z0-9_@-]+\z/
        # Don't look up strings unless they look like they could be a file
        # extension known to mime-types.
        #
        # There currently isn't any API public way to look up extensions
        # directly out of MIME::Types, but the type_for() method only strips
        # off after a period anyway.
        return ext
      end

      types = MIME::Types.type_for(ext)
      if types.empty?
        ext
      else
        types.first.content_type
      end
    end
  end
end
