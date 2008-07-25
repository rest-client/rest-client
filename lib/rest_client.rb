require 'uri'
require 'net/https'

require File.dirname(__FILE__) + '/rest_client/resource'
require File.dirname(__FILE__) + '/rest_client/request_errors'
require File.dirname(__FILE__) + '/rest_client/payload'
require File.dirname(__FILE__) + '/rest_client/net_http_ext'

# This module's static methods are the entry point for using the REST client.
#
#   # GET
#   xml = RestClient.get 'http://example.com/resource'
#   jpg = RestClient.get 'http://example.com/resource', :accept => 'image/jpg'
#
#   # authentication and SSL
#   RestClient.get 'https://user:password@example.com/private/resource'
#
#   # POST or PUT with a hash sends parameters as a urlencoded form body
#   RestClient.post 'http://example.com/resource', :param1 => 'one'
#
#   # nest hash parameters
#   RestClient.post 'http://example.com/resource', :nested => { :param1 => 'one' }
#
#   # POST and PUT with raw payloads
#   RestClient.post 'http://example.com/resource', 'the post body', :content_type => 'text/plain'
#   RestClient.post 'http://example.com/resource.xml', xml_doc
#   RestClient.put 'http://example.com/resource.pdf', File.read('my.pdf'), :content_type => 'application/pdf'
#
#   # DELETE
#   RestClient.delete 'http://example.com/resource'
#
# For live tests of RestClient, try using http://rest-test.heroku.com, which echoes back information about the rest call:
#
#   >> RestClient.put 'http://rest-test.heroku.com/resource', :foo => 'baz'
#   => "PUT http://rest-test.heroku.com/resource with a 7 byte payload, content type application/x-www-form-urlencoded {\"foo\"=>\"baz\"}"
#
module RestClient
	def self.get(url, headers={}, &b)
		Request.execute(:method => :get,
			:url => url,
			:headers => headers, &b)
	end

	def self.post(url, payload, headers={}, &b)
		Request.execute(:method => :post,
			:url => url,
			:payload => payload,
			:headers => headers, &b)
	end

	def self.put(url, payload, headers={}, &b)
		Request.execute(:method => :put,
			:url => url,
			:payload => payload,
			:headers => headers, &b)
	end

	def self.delete(url, headers={}, &b)
		Request.execute(:method => :delete,
			:url => url,
			:headers => headers, &b)
	end

	# Internal class used to build and execute the request.
	class Request
		attr_reader :method, :url, :headers, :user, :password

		def self.execute(args, &b)
			new(args).execute(&b)
		end

		def initialize(args)
			@method = args[:method] or raise ArgumentError, "must pass :method"
			@url = args[:url] or raise ArgumentError, "must pass :url"
			@payload = Payload.generate(args[:payload] || '')
			@headers = args[:headers] || {}
			@user = args[:user]
			@password = args[:password]
		end

		def execute(&b)
			execute_inner(&b)
		rescue Redirect => e
			@url = e.url
			execute(&b)
		end

		def execute_inner(&b)
			uri = parse_url_with_auth(url)
			transmit(uri, net_http_class(method).new(uri.request_uri, make_headers(headers)), payload, &b)
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
			Net::HTTP.const_get(method.to_s.capitalize)
		end

		def parse_url(url)
			url = "http://#{url}" unless url.match(/^http/)
			URI.parse(url)
		end

		def parse_url_with_auth(url)
			uri = parse_url(url)
			@user = uri.user if uri.user
			@password = uri.password if uri.password
			uri
		end

		def process_payload(p=nil, parent_key=nil)
			unless p.is_a?(Hash)
				p
			else
				@headers[:content_type] ||= 'application/x-www-form-urlencoded'
				p.keys.map do |k|
					key = parent_key ? "#{parent_key}[#{k}]" : k
					if p[k].is_a? Hash
						process_payload(p[k], key)
					else
						value = URI.escape(p[k].to_s, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
						"#{key}=#{value}"
					end
				end.join("&")
			end
		end

		def transmit(uri, req, payload, &b)
			setup_credentials(req)

			net = Net::HTTP.new(uri.host, uri.port)
			net.use_ssl = uri.is_a?(URI::HTTPS)

			net.start do |http|
				## Ok. I know this is weird but it's a hack for now
				## this lets process_result determine if it should read the body
				## into memory or not
				process_result(http.request(req, payload || "", &b), &b)
			end
		rescue EOFError
			raise RestClient::ServerBrokeConnection
		rescue Timeout::Error
			raise RestClient::RequestTimeout
		ensure
			payload.close
		end

		def setup_credentials(req)
			req.basic_auth(user, password) if user
		end

		def process_result(res, &b)
			if %w(200 201 202).include? res.code
				return res.body unless b
			elsif %w(301 302 303).include? res.code
				url = res.header['Location']

				if url !~ /^http/
					uri = URI.parse(@url)
					uri.path = "/#{url}".squeeze('/')
					url = uri.to_s
				end

				raise Redirect, url
			elsif res.code == "401"
				raise Unauthorized
			elsif res.code == "404"
				raise ResourceNotFound
			else
				raise RequestFailed, res
			end
		end
		
		def payload
			@payload
		end

		def default_headers
			@payload.headers.merge({ :accept => 'application/xml' })
		end
	end
end
