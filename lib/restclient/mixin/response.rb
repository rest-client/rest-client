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

			def self.included(receiver)
				receiver.extend(RestClient::Mixin::Response::ClassMethods)
			end

			module ClassMethods
				def beautify_headers(headers)
					headers.inject({}) do |out, (key, value)|
						out[key.gsub(/-/, '_').to_sym] = value.first
					out
					end
				end
			end
		end
	end
end
