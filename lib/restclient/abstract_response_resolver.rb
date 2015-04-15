require 'cgi'
require 'http-cookie'
require 'forwardable'

module RestClient

  class AbstractResponseResolver
    extend Forwardable

    def_delegators :response, :code, :args, :headers, :request

    def initialize(response)
      @response = response
    end

    # Return the default behavior corresponding to the response code:
    # the response itself for code in 200..206, redirection for 301, 302 and 307 in get and head cases, redirection for 303 and an exception in other cases
    def return! request = nil, result = nil, & block
      if (200..207).include? code
        response
      elsif [301, 302, 307].include? code
        unless [:get, :head].include? args[:method]
          raise Exceptions::EXCEPTIONS_MAP[code].new(response, code)
        else
          follow_redirection(request, result, & block)
        end
      elsif code == 303
        args[:method] = :get
        args.delete :payload
        follow_redirection(request, result, & block)
      elsif Exceptions::EXCEPTIONS_MAP[code]
        raise Exceptions::EXCEPTIONS_MAP[code].new(response, code)
      else
        raise RequestFailed.new(response, code)
      end
    end

    # Follow a redirection
    #
    # @param request [RestClient::Request, nil]
    # @param result [Net::HTTPResponse, nil]
    #
    def follow_redirection request = nil, result = nil, & block
      new_args = response.args.dup

      url = response.headers[:location]
      if url !~ /^http/
        url = URI.parse(request.url).merge(url).to_s
      end
      new_args[:url] = url
      if request
        raise MaxRedirectsReached if request.max_redirects == 0
        update_args_after_redirect!(new_args)
      end

      Request.execute(new_args, &block)
    end


    # Cookie jar extracted from response headers.
    #
    # @return [HTTP::CookieJar]
    #
    def cookie_jar
      return @cookie_jar if @cookie_jar

      jar = HTTP::CookieJar.new
      headers.fetch(:set_cookie, []).each do |cookie|
        jar.parse(cookie, request.url)
      end

      @cookie_jar = jar
    end

    protected

    attr_reader :response

    private

    # Decrease count of passed redirections
    def update_args_after_redirect!(args)
      args[:password] = request.password
      args[:user] = request.user
      args[:headers] = request.headers
      args[:max_redirects] = request.max_redirects - 1

      # TODO: figure out what to do with original :cookie, :cookies values
      args[:headers]['Cookie'] = HTTP::Cookie.cookie_value(
        cookie_jar.cookies(args.fetch(:url)))
    end

  end
end
