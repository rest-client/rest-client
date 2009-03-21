require File.dirname(__FILE__) + '/mixin/response'

module RestClient
	# The response from RestClient looks like a string, but is actually one of
	# these.  99% of the time you're making a rest call all you care about is
	# the body, but on the occassion you want to fetch the headers you can:
	#
	#   RestClient.get('http://example.com').headers[:content_type]
	#
	class Response < String

		include RestClient::Mixin::Response

		def initialize(string, net_http_res)
			@net_http_res = net_http_res
			super(string || "")
		end

	end
end
