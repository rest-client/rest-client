module RestClient

  # A Response from RestClient, you can access the response body, the code or the headers.
  #
  module Response

    include AbstractResponse

    def body
      @body ||= String.new(self)
    end

    def self.create body, net_http_res, args, request
      result = body || ''
      result.extend Response

      result.response_set_vars(net_http_res, args, request)
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

      response.force_encoding(encoding)

      response
    end
  end
end
