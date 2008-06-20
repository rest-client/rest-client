require 'uri'
require 'net/https'

require File.dirname(__FILE__) + '/resource'
require File.dirname(__FILE__) + '/request_errors'

# This module's static methods are the entry point for using the REST client.
module RestClient
	def self.get(url, headers={})
		Request.execute(:method => :get,
			:url => url,
			:headers => headers)
	end

	def self.post(url, payload, headers={})
		Request.execute(:method => :post,
			:url => url,
			:payload => payload,
			:headers => headers)
	end

	def self.put(url, payload, headers={})
		Request.execute(:method => :put,
			:url => url,
			:payload => payload,
			:headers => headers)
	end

	def self.delete(url, headers={})
		Request.execute(:method => :delete,
			:url => url,
			:headers => headers)
	end

	# Internal class used to build and execute the request.
	class Request
		attr_reader :method, :url, :payload, :headers, :user, :password

		def self.execute(args)
			new(args).execute
		end

		def initialize(args)
			@method = args[:method] or raise ArgumentError, "must pass :method"
			@url = args[:url] or raise ArgumentError, "must pass :url"
			@headers = args[:headers] || {}
			@payload = process_payload(args[:payload])
			@user = args[:user]
			@password = args[:password]
		end

		def execute
			execute_inner
		rescue Redirect => e
			@url = e.message
			execute
		end

		def execute_inner
			uri = parse_url(url)
			transmit uri, net_http_class(method).new(uri.request_uri, make_headers(headers)), payload
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

		def process_payload(p=nil)
			unless p.is_a?(Hash)
				p
			else
				@headers[:content_type] = 'application/x-www-form-urlencoded'
				p.keys.map { |k| 
					v = URI.escape(p[k].to_s, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
					"#{k}=#{v}"
				}.join("&")
			end
		end

		def transmit(uri, req, payload)
			setup_credentials(req)

			net = Net::HTTP.new(uri.host, uri.port)
			net.use_ssl = uri.is_a?(URI::HTTPS)

			net.start do |http|
				process_result http.request(req, payload || "")
			end
		end

		def setup_credentials(req)
			req.basic_auth(user, password) if user
		end

		def process_result(res)
			if %w(200 201 202).include? res.code
				res.body
			elsif %w(301 302 303).include? res.code
				raise Redirect, res.header['Location']
			elsif res.code == "401"
				raise Unauthorized
			else
				raise RequestFailed, res
			end
		end

		def default_headers
			{ :accept => 'application/xml' }
		end
	end
end
