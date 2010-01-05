require 'tempfile'
require 'mime/types'

module RestClient
  # This class is used internally by RestClient to send the request, but you can also
  # call it directly if you'd like to use a method not supported by the
  # main API.  For example:
  #
  #   RestClient::Request.execute(:method => :head, :url => 'http://example.com')
  #
  # Mandatory parameters:
  # * :method
  # * :url
  # Optional parameters (have a look at ssl and/or uri for some explanations):
  # * :headers a hash containing the request headers
  # * :cookies will replace possible cookies in the :headers
  # * :user and :password for basic auth, will be replaced by a user/password available in the :url
  # * :raw_response return a low-level RawResponse instead of a Response
  # * :verify_ssl enable ssl verification, possible values are constants from OpenSSL::SSL
  # * :timeout and :open_timeout
  # * :ssl_client_cert, :ssl_client_key, :ssl_ca_file
  class Request
    attr_reader :method, :url, :payload, :headers, :processed_headers,
                :cookies, :user, :password, :timeout, :open_timeout,
                :verify_ssl, :ssl_client_cert, :ssl_client_key, :ssl_ca_file,
                :raw_response

    def self.execute(args)
      new(args).execute
    end

    def initialize(args)
      @method = args[:method] or raise ArgumentError, "must pass :method"
      @url = args[:url] or raise ArgumentError, "must pass :url"
      @headers = args[:headers] || {}
      @cookies = @headers.delete(:cookies) || args[:cookies] || {}
      @payload = Payload.generate(args[:payload])
      @user = args[:user]
      @password = args[:password]
      @timeout = args[:timeout]
      @open_timeout = args[:open_timeout]
      @raw_response = args[:raw_response] || false
      @verify_ssl = args[:verify_ssl] || false
      @ssl_client_cert = args[:ssl_client_cert] || nil
      @ssl_client_key = args[:ssl_client_key] || nil
      @ssl_ca_file = args[:ssl_ca_file] || nil
      @tf = nil # If you are a raw request, this is your tempfile
      @processed_headers = make_headers headers
    end

    def execute
      execute_inner
    rescue Redirect => e
      @url = e.url
      @method = :get
      @payload = nil
      execute
    end

    def execute_inner
      uri = parse_url_with_auth(url)
      transmit uri, net_http_request_class(method).new(uri.request_uri, processed_headers), payload
    end

    def make_headers user_headers
      unless @cookies.empty?
        user_headers[:cookie] = @cookies.map {|key, val| "#{key.to_s}=#{val}" }.join('; ')
      end

      headers = default_headers.merge(user_headers).inject({}) do |final, (key, value)|
        target_key = key.to_s.gsub(/_/, '-').capitalize
        if 'CONTENT-TYPE' == target_key.upcase
          target_value = value.to_s
          final[target_key] = MIME::Types.type_for_extension target_value
        elsif 'ACCEPT' == target_key.upcase
            # Accept can be composed of several comma-separated values
            if value.is_a? Array
              target_values = value
            else
              target_values = value.to_s.split ','
            end
            final[target_key] = target_values.map{ |ext| MIME::Types.type_for_extension(ext.to_s.strip)}.join(', ')
        else
          final[target_key] = value.to_s
        end
        final
      end

      headers.merge!(@payload.headers) if @payload
      headers
    end

    def net_http_class
      if RestClient.proxy
        proxy_uri = URI.parse(RestClient.proxy)
        Net::HTTP::Proxy(proxy_uri.host, proxy_uri.port, proxy_uri.user, proxy_uri.password)
      else
        Net::HTTP
      end
    end

    def net_http_request_class(method)
      Net::HTTP.const_get(method.to_s.capitalize)
    end

    def parse_url(url)
      url = "http://#{url}" unless url.match(/^http/)
      URI.parse(url)
    end

    def parse_url_with_auth(url)
      uri = parse_url(url)
      @user = uri.user if uri.user
      @password = uri.password if uri.password
      uri
    end

    def process_payload(p=nil, parent_key=nil)
      unless p.is_a?(Hash)
        p
      else
        @headers[:content_type] ||= 'application/x-www-form-urlencoded'
        p.keys.map do |k|
          key = parent_key ? "#{parent_key}[#{k}]" : k
          if p[k].is_a? Hash
            process_payload(p[k], key)
          else
            value = URI.escape(p[k].to_s, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
            "#{key}=#{value}"
          end
        end.join("&")
      end
    end

    def transmit(uri, req, payload)
      setup_credentials(req)

      net = net_http_class.new(uri.host, uri.port)
      net.use_ssl = uri.is_a?(URI::HTTPS)
      if @verify_ssl == false
        net.verify_mode = OpenSSL::SSL::VERIFY_NONE
      elsif @verify_ssl.is_a? Integer
        net.verify_mode = @verify_ssl
      end
      net.cert = @ssl_client_cert if @ssl_client_cert
      net.key = @ssl_client_key if @ssl_client_key
      net.ca_file = @ssl_ca_file if @ssl_ca_file
      net.read_timeout = @timeout if @timeout
      net.open_timeout = @open_timeout if @open_timeout

      display_log request_log

      net.start do |http|
        res = http.request(req, payload) { |http_response| fetch_body(http_response) }
        result = process_result(res)
        display_log response_log(res)

        if result.kind_of?(String) or @method == :head
          Response.new(result, res)
        elsif @raw_response
          RawResponse.new(@tf, res)
        else
          Response.new(nil, res)
        end
      end
    rescue EOFError
      raise RestClient::ServerBrokeConnection
    rescue Timeout::Error
      raise RestClient::RequestTimeout
    end

    def setup_credentials(req)
      req.basic_auth(user, password) if user
    end

    def fetch_body(http_response)
      if @raw_response
        # Taken from Chef, which as in turn...
        # Stolen from http://www.ruby-forum.com/topic/166423
        # Kudos to _why!
        @tf = Tempfile.new("rest-client")
        size, total = 0, http_response.header['Content-Length'].to_i
        http_response.read_body do |chunk|
          @tf.write(chunk)
          size += chunk.size
          if size == 0
            display_log("#{@method} #{@url} done (0 length file)")
          elsif total == 0
            display_log("#{@method} #{@url} (zero content length)")
          else
            display_log("#{@method} #{@url} %d%% done (%d of %d)" % [(size * 100) / total, size, total])
          end
        end
        @tf.close
        @tf
      else
        http_response.read_body
      end
      http_response
    end

    def process_result(res)
      if res.code =~ /\A2\d{2}\z/
        # We don't decode raw requests
        unless @raw_response
          self.class.decode res['content-encoding'], res.body if res.body
        end
      elsif %w(301 302 303).include? res.code
        url = res.header['Location']

        if url !~ /^http/
          uri = URI.parse(@url)
          uri.path = "/#{url}".squeeze('/')
          url = uri.to_s
        end

        raise Redirect, url
      elsif res.code == "304"
        raise NotModified, res
      elsif res.code == "401"
        raise Unauthorized, res
      elsif res.code == "404"
        raise ResourceNotFound, res
      else
        raise RequestFailed, res
      end
    end

    def self.decode(content_encoding, body)
      if content_encoding == 'gzip' and not body.empty?
        Zlib::GzipReader.new(StringIO.new(body)).read
      elsif content_encoding == 'deflate'
        Zlib::Inflate.new.inflate(body)
      else
        body
      end
    end

    def request_log
      if RestClient.log
        out = []
        out << "RestClient.#{method} #{url.inspect}"
        out << "headers: #{processed_headers.inspect}"
        out << "payload: #{payload.short_inspect}" if payload
        out.join(', ')
      end
    end

    def response_log(res)
      size = @raw_response ? File.size(@tf.path) : (res.body.nil? ? 0 : res.body.size)
      "# => #{res.code} #{res.class.to_s.gsub(/^Net::HTTP/, '')} | #{(res['Content-type'] || '').gsub(/;.*$/, '')} #{size} bytes"
    end

    def display_log(msg)
      return unless log_to = RestClient.log

      if log_to == 'stdout'
        STDOUT.puts msg
      elsif log_to == 'stderr'
        STDERR.puts msg
      else
        File.open(log_to, 'a') { |f| f.puts msg }
      end
    end

    def default_headers
      { :accept => '*/*; q=0.5, application/xml', :accept_encoding => 'gzip, deflate' }
    end
  end
end

module MIME
  class Types

    # Return the first found content-type for a value considered as an extension or the value itself
    def type_for_extension ext
      candidates =  @extension_index[ext]
      candidates.empty? ? ext : candidates[0].content_type
    end

    class << self
      def type_for_extension ext
        @__types__.type_for_extension ext
      end
    end
  end
end
