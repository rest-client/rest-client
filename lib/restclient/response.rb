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
    end

    private

    def self.fix_encoding(response)
      charset  = response.headers[:content_type].to_s[/\bcharset=([^ ]+)/, 1]
      encoding = nil

      begin
        encoding = Encoding.find(charset) unless charset.nil?
      rescue ArgumentError => e
        RestClient.log "No such encoding: #{charset}"
      end

      if encoding && response.body.clone.force_encoding(encoding).valid_encoding?
        response.body.force_encoding(encoding)
      end

      response
    end

  end
end
