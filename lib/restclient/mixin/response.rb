module RestClient
  module Mixin
    module Response
      attr_reader :net_http_res

      # HTTP status code, always 200 since RestClient throws exceptions for
      # other codes.
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
        @cookies ||= (self.headers[:set_cookie] || []).inject({}) do |out, cookie|
          key, *val = cookie.split(";").first.split("=")
          out[key] = val.join("=")
          out
        end
      end

      def self.included(receiver)
        receiver.extend(RestClient::Mixin::Response::ClassMethods)
      end

      module ClassMethods
        def beautify_headers(headers)
          headers.inject({}) do |out, (key, value)|
            out[key.gsub(/-/, '_').downcase.to_sym] = %w{set-cookie}.include?(key.downcase) ? value : value.first
            out
          end
        end
      end
    end
  end
end
