require 'uri'
require 'net/http'
require 'rexml/document'

module RestClient
	def self.get(url, headers={})
		Request.new(:get, url, nil, headers).execute
	end

	def self.post(url, payload=nil, headers={})
		Request.new(:post, url, payload, headers).execute
	end

	def self.put(url, payload=nil, headers={})
		Request.new(:put, url, payload, headers).execute
	end

	def self.delete(url, headers={})
		Request.new(:delete, url, nil, headers).execute
	end

	class Request
		attr_reader :method, :url, :payload, :headers

		def initialize(method, url, payload, headers)
			@method = method
			@url = url
			@payload = payload
			@headers = headers
		end

		def execute
			execute_inner
		rescue Redirect => e
			@url = e.message
			execute
		end

		def execute_inner
			uri = parse_url(url)
			transmit uri, net_http_class(method).new(uri.path, make_headers(headers)), payload
		end

		def make_headers(user_headers)
			final = {}
			merged = default_headers.merge(user_headers)
			merged.keys.each do |key|
				final[key.to_s.gsub(/_/, '-').capitalize] = merged[key]
			end
			final
		end

		def net_http_class(method)
			Object.module_eval "Net::HTTP::#{method.to_s.capitalize}"
		end

		def parse_url(url)
			url = "http://#{url}" unless url.match(/^http/)
			URI.parse(url)
		end

		class Redirect < Exception; end
		class RequestFailed < Exception; end
		class Unauthorized < Exception; end

		def transmit(uri, req, payload)
			Net::HTTP.start(uri.host, uri.port) do |http|
				process_result http.request(req, payload || "")
			end
		end

		def process_result(res)
			if %w(200 201 202).include? res.code
				res.body
			elsif %w(301 302 303).include? res.code
				raise Redirect, res.header['Location']
			elsif res.code == "401"
				raise Unauthorized
			else
				raise RequestFailed, error_message(res)
			end
		end

		def error_message(res)
			"HTTP code #{res.code}: #{res.body}"
		end

		def default_headers
			{ :accept => 'application/xml' }
		end
	end
end
