module RestClient2
  # The response from RestClient2 on a raw request looks like a string, but is
  # actually one of these.  99% of the time you're making a rest call all you
  # care about is the body, but on the occassion you want to fetch the
  # headers you can:
  #
  #   RestClient2.get('http://example.com').headers[:content_type]
  #
  # In addition, if you do not use the response as a string, you can access
  # a Tempfile object at res.file, which contains the path to the raw
  # downloaded request body.
  class RawResponse

    include AbstractResponse

    attr_reader :file, :request, :start_time, :end_time

    def inspect
      "<RestClient2::RawResponse @code=#{code.inspect}, @file=#{file.inspect}, @request=#{request.inspect}>"
    end

    # @param [Tempfile] tempfile The temporary file containing the body
    # @param [Net::HTTPResponse] net_http_res
    # @param [RestClient2::Request] request
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

    def body
      @file.rewind
      @file.read
    end

    def size
      file.size
    end

  end
end
