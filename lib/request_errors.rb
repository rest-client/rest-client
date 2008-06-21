require 'rexml/document'

module RestClient
	# A redirect was encountered; caught by execute to retry with the new url.
	class Redirect < RuntimeError; end

	# Authorization is required to access the resource specified.
	class Unauthorized < RuntimeError; end

	# The request failed, meaning the remote HTTP server returned a code other
	# than success, unauthorized, or redirect.
	#
	# The exception message attempts to extract the error from the XML, using
	# format returned by Rails: <errors><error>some message</error></errors>
	#
	# You can get the status code by e.http_code, or see anything about the
	# response via e.response.  For example, the entire result body (which is
	# probably an HTML error page) is e.response.body.
	class RequestFailed < RuntimeError
		attr_accessor :response

		def initialize(response)
			@response = response
		end

		def http_code
			@response.code.to_i
		end

		def message(default = "Unknown error")
			return "Resource not found" if http_code == 404
			parse_error_xml rescue default
		end

		def parse_error_xml
			xml_errors = REXML::Document.new(@response.body).elements.to_a("//errors/error")
			xml_errors.empty? ? raise : xml_errors.map { |a| a.text }.join(" / ")
		end
	end
end

# backwards compatibility
RestClient::Resource::Redirect = RestClient::Redirect
RestClient::Resource::Unauthorized = RestClient::Unauthorized
RestClient::Resource::RequestFailed = RestClient::RequestFailed
