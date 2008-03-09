require 'uri'
require 'net/http'
require 'rexml/document'

module RestClient
	def self.get(url)
		do_request :get, url
	end

	def self.post(url, payload=nil)
		do_request :post, url, payload
	end

	def self.put(url, payload=nil)
		do_request :put, url, payload
	end

	def self.delete(url)
		do_request :delete, url
	end

	####

	def self.do_request(method, url, payload=nil)
		do_request_inner(method, url, payload)
	rescue Redirect => e
		do_request(method, e.message, payload)
	end

	def self.do_request_inner(method, url, payload=nil)
		uri = parse_url(url)
		transmit uri, net_http_class(method).new(uri.path, headers), payload
	end

	def self.net_http_class(method)
		Object.module_eval "Net::HTTP::#{method.to_s.capitalize}"
	end

	def self.parse_url(url)
		url = "http://#{url}" unless url.match(/^http/)
		URI.parse(url)
	end

	class Redirect < Exception; end
	class RequestFailed < Exception; end
	class Unauthorized < Exception; end

	def self.transmit(uri, req, payload)
		Net::HTTP.start(uri.host, uri.port) do |http|
			process_result http.request(req, payload || "")
		end
	end

	def self.process_result(res)
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

	def self.parse_error_xml(body)
		xml(body).elements.to_a("//errors/error").map { |a| a.text }.join(" / ")
	rescue
		"unknown error"
	end

	def self.error_message(res)
		"HTTP code #{res.code}: #{parse_error_xml(res.body)}"
	end

	def self.headers
		{ 'Accept' => 'application/xml' }
	end

	def self.xml(raw)
		REXML::Document.new(raw)
	end
end
