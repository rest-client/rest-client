require 'uri'
require 'net/http'
require 'rexml/document'

module Rest
	def self.get(url)
		uri = parse_url(url)
		transmit uri, Net::HTTP::Get.new(uri.path, headers)
	end

	def self.post(url, payload=nil)
		uri = parse_url(url)
		transmit uri, Net::HTTP::Post.new(uri.path, headers), payload
	end

	def self.put(url, payload=nil)
		uri = parse_url(url)
		transmit uri, Net::HTTP::Put.new(uri.path, headers), payload
	end

	def self.delete(url)
		uri = parse_url(url)
		transmit uri, Net::HTTP::Delete.new(uri.path, headers)
	end

	####

	def self.parse_url(url)
		url = "http://#{url}" unless url.match(/^http/)
		URI.parse(url)
	end

	def self.transmit(uri, req, payload=nil)    # :nodoc:
		Net::HTTP.start(uri.host, uri.port) do |http|
			process_result http.request(req, payload)
		end
	end

	class RequestFailed < Exception; end
	class Unauthorized < Exception; end

	def self.process_result(res)
		if %w(200 201 202).include? res.code
			res.body
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
