module RestClient

  # A Response from RestClient, you can access the response body, the code or the headers.
  #
  class Response < AbstractResponse

    attr_reader :body

    def initialize(body, net_http_res)
      @net_http_res = net_http_res
      @body = body || ""
    end

    def method_missing symbol, *args
      if body.respond_to? symbol
        warn "[warning] The Response is no more a String, please update your code"
        body.send symbol, *args
      else
        super
      end
    end

    def to_s
      body.to_s
    end

    def inspect
      "Code #{code} #{headers[:content_type] ? "#{headers[:content_type] } ": ''} #{body.size} byte(s)"
    end

  end
end
