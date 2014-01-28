module RestClient
  module Util
    extend self

    def net_http_class
      if RestClient.proxy
        proxy_uri = URI.parse(RestClient.proxy)
        Net::HTTP::Proxy(
          proxy_uri.host, proxy_uri.port, proxy_uri.user, proxy_uri.password)
      else
        Net::HTTP
      end
    end

    def net_http_request_class(method)
      Net::HTTP.const_get(method.to_s.capitalize)
    end

    def parse_url(url)
      url = "http://#{url}" unless url.match(/^http/)
      URI.parse(URI::escape(url))
    end
  end
end
