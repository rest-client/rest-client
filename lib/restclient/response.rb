module RestClient

  # A Response from RestClient, you can access the response body, the code or the headers.
  #
  module Response

    include AbstractResponse

    attr_accessor :args, :body, :net_http_res

    def body
      self
    end

    def Response.create body, net_http_res, args
      result = body || ''
      if result.respond_to?(:force_encoding)
        if (charset = net_http_res.type_params['charset'])
          result.force_encoding(charset)
        end
      end
      result.extend Response
      result.net_http_res = net_http_res
      result.args = args
      result
    end

  end
end
