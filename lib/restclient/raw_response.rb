module RestClient

  # {RawResponse} is used to represent RestClient responses when
  # `:raw_response => true` is passed to the {Request}.
  #
  # Instead of processing the response data in various ways, the `RawResponse`
  # downloads the response body to a `Tempfile` and does little processing of
  # the underlying `Net::HTTPResponse` object. This is especially useful for
  # large downloads when you don't want to load the entire response into
  # memory.
  #
  # Use {#file} to access the `Tempfile` containing the raw response body. The
  # file path is accessible at `.file.path`.
  #
  # **Note that like all `Tempfile` objects, the {#file} will be deleted when
  # the object is dereferenced.**
  #
  # This class brings in all the common functionality from {AbstractResponse},
  # such as {AbstractResponse.headers}, etc.
  #
  # @example
  #
  #   r = RestClient::Request.execute(method: :get, url: 'http://example.com', raw_response: true)
  #   r.code
  #   # => 200
  #   puts r.file.inspect
  #   # => #<Tempfile:/tmp/rest-client.20170102-15213-b8kgcj>
  #   r.file.path
  #   # => "/tmp/rest-client.20170102-15213-b8kgcj"
  #   r.size
  #   # => 1270
  #
  class RawResponse

    include AbstractResponse

    attr_reader :file, :request, :start_time, :end_time

    def inspect
      "<RestClient::RawResponse @code=#{code.inspect}, @file=#{file.inspect}, @request=#{request.inspect}>"
    end

    # @param [Tempfile] tempfile The temporary file containing the body
    # @param [Net::HTTPResponse] net_http_res
    # @param [RestClient::Request] request
    # @param [Time] start_time
    def initialize(tempfile, net_http_res, request, start_time=nil)
      @file = tempfile

      # reopen the tempfile so we can read it
      @file.open

      response_set_vars(net_http_res, request, start_time)
    end

    def to_s
      body
    end

    # Read the response body from {#file} into memory and return as a String.
    #
    # @return [String]
    #
    def body
      @file.rewind
      @file.read
    end

    # Return the response body file size.
    #
    # @return [Integer]
    def size
      file.size
    end

  end
end
