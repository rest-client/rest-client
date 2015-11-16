module RestClient

  # A Response from RestClient, you can access the response body, the code or the headers.
  #
  class Response < String

    include AbstractResponse

    # Return the HTTP response body.
    #
    # Future versions of RestClient will deprecate treating response objects
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

    def inspect
      "<RestClient::Response #{code.inspect} #{body_truncated(10).inspect}>"
    end

    def self.create(body, net_http_res, args, request)
      result = self.new(body || '')

      result.response_set_vars(net_http_res, args, request)
      fix_encoding(result)

      result
    end

    private

    # Automatically set the encoding of the response object based on the
    # presence of a Content-Type... charset header.
    #
    # If a charset is found and represents a valid encoding, call
    # force_encoding on the response to alter it to the correct representation.
    #
    # @param [Response] response
    #
    # @return [Encoding,nil]
    #
    def self.fix_encoding(response)
      charset = RestClient::Utils.get_encoding_from_headers(response.headers)
      return unless charset

      encoding = RestClient::Utils.find_encoding(charset)

      if encoding
        response.force_encoding(encoding)
      elsif RestClient.log
        RestClient.log << "No such encoding: #{charset.inspect}"
      end

      encoding
    end

    def body_truncated(length)
      if body.length > length
        body[0..length] + '...'
      else
        body
      end
    end
  end
end
