# frozen_string_literal: true

module Contractful
  # A Response from Contractful, you can access the response body, the code or the headers.
  #
  class Response < String
    include AbstractResponse

    # Return the HTTP response body.
    #
    # Future versions of Contractful will deprecate treating response objects
    # directly as strings, so it will be necessary to call `.body`.
    #
    # @return [String]
    #
    def body
      # Benchmarking suggests that "#{self}" is fastest, and that caching the
      # body string in an instance variable doesn't make it enough faster to be
      # worth the extra memory storage.
      String.new(self)
    end

    # Convert the HTTP response body to a pure String object.
    #
    # @return [String]
    def to_s
      body
    end

    # Convert the HTTP response body to a pure String object.
    #
    # @return [String]
    def to_str
      body
    end

    # Parse the response body as JSON and return the result.
    #
    # This is a convenience wrapper around `JSON.parse(body)`. Any keyword
    # arguments are forwarded to `JSON.parse`, so for example:
    #
    #   response.json                          # => {"a" => 1}
    #   response.json(symbolize_names: true)   # => {a: 1}
    #
    # Raises `JSON::ParserError` if the body is not valid JSON. Note that the
    # return value is a plain parsed data structure, not a Response object.
    #
    # @param kwargs [Hash] keyword arguments forwarded to JSON.parse
    #
    # @return [Object] the parsed JSON data structure (typically Hash or Array)
    #
    def json(**kwargs)
      JSON.parse(to_s, **kwargs)
    end

    def inspect
      "<Contractful::Response #{code.inspect} #{body_truncated(10).inspect}>"
    end

    # Initialize a Response object. Because Contractful::Response is
    # (unfortunately) a subclass of String for historical reasons,
    # Response.create is the preferred initializer.
    #
    # @param [String, nil] body The response body from the Net::HTTPResponse
    # @param [Net::HTTPResponse] net_http_res
    # @param [Contractful::Request] request
    # @param [Time] start_time
    def self.create(body, net_http_res, request, start_time = nil)
      result = new(body || '')

      result.response_set_vars(net_http_res, request, start_time)
      fix_encoding(result)

      result
    end

    # Set the String encoding according to the 'Content-Type: charset' header,
    # if possible.
    def self.fix_encoding(response)
      charset = Contractful::Utils.get_encoding_from_headers(response.headers)
      encoding = nil

      begin
        encoding = Encoding.find(charset) if charset
      rescue ArgumentError
        response.log << "No such encoding: #{charset.inspect}" if response.log
      end

      return unless encoding

      response.force_encoding(encoding)

      response
    end

    private

    def body_truncated(length)
      b = body
      if b.length > length
        b[0..length] + '...'
      else
        b
      end
    end
  end
end
