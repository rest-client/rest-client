require 'cgi'

module RestClient

  module AbstractResponse

    attr_reader :net_http_res, :args

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

    # Hash of cookies extracted from response headers
    def cookies
      @cookies ||= (self.headers[:set_cookie] || {}).inject({}) do |out, cookie_content|
        out.merge parse_cookie(cookie_content)
      end
    end

    def is_using_kerberos?
      # Possibility 1: We are sending a Kerberos token to the server.
      args_header = args[:headers] || {}
      args_auth = args_header[:authorization] || ''
      # Possibility 2: The server offers negotiate HTTP authentication.
      return ((args_auth.start_with? 'Negotiate') ||
              (headers[:www_authenticate] == 'Negotiate'))
    end

    # Return the default behavior corresponding to the response code:
    # the response itself for code in 200..206, redirection for 301, 302 and 307 in get and head cases, redirection for 303 and an exception in other cases
    def return! request = nil, result = nil, & block
      if (200..207).include? code
        self
      elsif [301, 302, 307].include? code
        unless [:get, :head].include? args[:method]
          raise Exceptions::EXCEPTIONS_MAP[code].new(self, code)
        else
          follow_redirection(request, result, & block)
        end
      elsif code == 303
        args[:method] = :get
        args.delete :payload
        follow_redirection(request, result, & block)
      elsif (code == 401) && is_using_kerberos?
        authenticate_negotiate(request, result, & block)
      elsif Exceptions::EXCEPTIONS_MAP[code]
        raise Exceptions::EXCEPTIONS_MAP[code].new(self, code)
      else
        raise RequestFailed.new(self, code)
      end
    end

    def to_i
      code
    end

    def description
      "#{code} #{STATUSES[code]} | #{(headers[:content_type] || '').gsub(/;.*$/, '')} #{size} bytes\n"
    end

    # Follow a redirection
    def follow_redirection request = nil, result = nil, & block
      url = headers[:location]
      if url !~ /^http/
        url = URI.parse(args[:url]).merge(url).to_s
      end
      args[:url] = url
      if request
        if request.max_redirects == 0
          raise MaxRedirectsReached
        end
        args[:password] = request.password
        args[:user] = request.user
        args[:headers] = request.headers
        args[:max_redirects] = request.max_redirects - 1
        # pass any cookie set in the result
        if result && result['set-cookie']
          args[:headers][:cookies] = (args[:headers][:cookies] || {}).merge(parse_cookie(result['set-cookie']))
        end
      end
      Request.execute args, &block
    end

    def authenticate_negotiate request = nil, result = nil, & block
      begin
        require 'base64'
        require 'gssapi'
      rescue LoadError
        # If the 'gssapi' gem is not installed, we tell the user how to fix the
        # problem and raise a 401 exception.
        warn "[warning] Server requests Negotiate HTTP authentication, but the gssapi ruby gem could not be loaded. Use 'gem install gssapi'."
        raise RequestFailed.new(self, 401)
      end

      uri = URI.parse(args[:url])
      gsscli = GSSAPI::Simple.new(uri.hostname, 'HTTP')
      token = gsscli.init_context
      ext_head = "Negotiate #{Base64.strict_encode64(token)}"

      # Request the same URL, but with the new Authorization header.
      if request
        # Make sure there is no basic authentication present.
        args.delete(:user)
        args[:headers] = request.headers
        args[:headers][:authorization] = ext_head
      end
      reply = Request.execute args, &block
      if !reply.headers[:www_authenticate]
        # If no WWW-Authenticate header is set, the request cannot be
        # successful (we need to verify that init_context with the header
        # value returns true).
        raise RequestFailed.new(self, 401)
      end

      itok = reply.headers[:www_authenticate].split(/\s+/).last
      if !gsscli.init_context(Base64.strict_decode64(itok))
        # According to RFC 4559, section 5, the reply cannot be used if the
        # final init_context with the WWW-Authenticate header value fails.
        raise RequestFailed.new(self, 401)
      end

      return reply
    end

    def AbstractResponse.beautify_headers(headers)
      headers.inject({}) do |out, (key, value)|
        out[key.gsub(/-/, '_').downcase.to_sym] = %w{ set-cookie }.include?(key.downcase) ? value : value.first
        out
      end
    end

    private

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
