require 'rexml/document'

module RestClient
	# A redirect was encountered; caught by execute to retry with the new url.
	class Redirect < RuntimeError; end

	# Authorization is required to access the resource specified.
	class Unauthorized < RuntimeError; end

	# Request failed with an unhandled http error code.
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