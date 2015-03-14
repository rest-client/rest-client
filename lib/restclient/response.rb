module RestClient

  # A Response from RestClient, you can access the response body, the code or the headers.
  #
  module Response

    include AbstractResponse

    attr_accessor :args, :net_http_res

    def body
      self
    end

    def self.create body, net_http_res, args
      result = body || ''
      result.extend Response
      result.net_http_res = net_http_res
      result.args = args
      fix_encoding(result)
      result
    end

    private

    def self.fix_encoding(response)
      charset = RestClient::Utils.get_encoding_from_headers(response.headers)
      encoding = nil

      begin
        encoding = Encoding.find(charset) if charset
      rescue ArgumentError
        RestClient.log "No such encoding: #{charset.inspect}"
      end

      return unless encoding

      response.body.force_encoding(encoding)

      response
    end
  end
end
