require File.dirname(__FILE__) + '/mixin/response'

module RestClient
	# The response from RestClient on a raw request looks like a string, but is 
	# actually one of these.  99% of the time you're making a rest call all you 
	# care about is the body, but on the occassion you want to fetch the 
	# headers you can:
	#
	#   RestClient.get('http://example.com').headers[:content_type]
	#
	# In addition, if you do not use the response as a string, you can access
	# a Tempfile object at res.file, which contains the path to the raw 
	# downloaded request body.  
	class RawResponse 
		include RestClient::Mixin::Response

		attr_reader :file

		def initialize(tempfile, net_http_res)
			@net_http_res = net_http_res
			@file = tempfile
		end

		def to_s
			@file.open
			@file.read
		end

	end
end
