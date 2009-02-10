module RestClient
	# The response from RestClient looks like a string, but is actually one of
	# these.  99% of the time you're making a rest call all you care about is
	# the body, but on the occassion you want to fetch the headers you can:
	#
	#   RestClient.get('http://example.com').headers[:content_type]
	#
	class Response < String
		attr_reader :net_http_res

		def initialize(string, net_http_res)
			@net_http_res = net_http_res
			super(string || "")
		end

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

    # Hash of cookies extracted from response headers
    def cookies
      @cookies ||= (self.headers[:set_cookie] || "").split('; ').inject({}) do |out, raw_c|
        key, val = raw_c.split('=')
        unless %w(expires domain path secure).member?(key)
          out[key] = val
        end
        out
      end
    end

		def self.beautify_headers(headers)
			headers.inject({}) do |out, (key, value)|
				out[key.gsub(/-/, '_').to_sym] = value.first
				out
			end
		end
	end
end
