module RestClient

  # A Response from RestClient, you can access the response body, the code or the headers.
  #
  class Response < AbstractResponse

    attr_reader :body

    WARNING_MESSAGE = '[warning] The Response is no more a String and the Response content is now accessed through Response.body, please update your code'

    def initialize body, net_http_res, args
      super net_http_res, args
      @body = body || ""
    end

    def method_missing symbol, *args
      if body.respond_to? symbol
        warn WARNING_MESSAGE
        body.send symbol, *args
      else
        super
      end
    end

    def == o
      if super
        true
      else
        equal_body = (body == o)
        if equal_body
          warn WARNING_MESSAGE
        end
        equal_body
      end
    end

    def to_s
      body.to_s
    end

    def size
      body.size
    end

  end
end
