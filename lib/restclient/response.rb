module RestClient
	class Response < String
		attr_reader :net_http_res

		def initialize(string, net_http_res)
			@net_http_res = net_http_res
			super string
		end

		def code
			@code ||= @net_http_res.code.to_i
		end

		def headers
			@headers ||= self.class.beautify_headers(@net_http_res.to_hash)
		end

		def self.beautify_headers(headers)
			headers.inject({}) do |out, (key, value)|
				out[key.gsub(/-/, '_').to_sym] = value.first
				out
			end
		end
	end
end
