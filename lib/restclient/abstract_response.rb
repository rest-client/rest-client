module RestClient

  class AbstractResponse

    attr_reader :net_http_res, :args

    def initialize net_http_res, args
      @net_http_res = net_http_res
      @args = args
    end

    # HTTP status code
    def code
      @code ||= @net_http_res.code.to_i
    end

    # A hash of the headers, beautified with symbols and underscores.
    # e.g. "Content-type" will become :content_type.
    def headers
      @headers ||= self.class.beautify_headers(@net_http_res.to_hash)
    end

    # The raw headers.
    def raw_headers
      @raw_headers ||= @net_http_res.to_hash
    end

    # Hash of cookies extracted from response headers
    def cookies
      @cookies ||= (self.headers[:set_cookie] || []).inject({}) do |out, cookie_content|
        # correctly parse comma-separated cookies containing HTTP dates (which also contain a comma)
        cookie_content.split(/,\s*/).inject([""]) { |array, blob|
          blob =~ /expires=.+?$/ ? array.push(blob) : array.last.concat(blob)
          array
        }.each do |cookie|
          next if cookie.empty?
          key, *val = cookie.split(";").first.split("=")
          out[key] = val.join("=")
        end
        out
      end
    end

    # Return the default behavior corresponding to the response code:
    # the response itself for code in 200..206, redirection for 301 and 302 in get and head cases, redirection for 303 and an exception in other cases
    def return! &block
      if (200..206).include? code
        self
      elsif [301, 302].include? code
        unless [:get, :head].include? args[:method]
          raise Exceptions::EXCEPTIONS_MAP[code], self
        else
          follow_redirection &block
        end
      elsif code == 303
        args[:method] = :get
        args.delete :payload
        follow_redirection &block
      elsif Exceptions::EXCEPTIONS_MAP[code]
        raise Exceptions::EXCEPTIONS_MAP[code], self
      else
        raise RequestFailed, self
      end
    end

    def inspect
      "#{code} #{STATUSES[code]} | #{(headers[:content_type] || '').gsub(/;.*$/, '')} #{size} bytes\n"
    end

    # Follow a redirection
    def follow_redirection &block
      url = headers[:location]
      if url !~ /^http/
        url = URI.parse(args[:url]).merge(url).to_s
      end
      args[:url] = url
      Request.execute args, &block
    end

    def AbstractResponse.beautify_headers(headers)
      headers.inject({}) do |out, (key, value)|
        out[key.gsub(/-/, '_').downcase.to_sym] = %w{set-cookie}.include?(key.downcase) ? value : value.first
        out
      end
    end
  end
end
