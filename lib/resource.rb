module RestClient
	# A class that can be instantiated for access to a RESTful resource,
	# including authentication.
	#
	# Example:
	#
	#   resource = RestClient::Resource.new('http://some/resource')
	#   jpg = resource.get(:accept => 'image/jpg')
	#
	# With HTTP basic authentication:
	#
	#   resource = RestClient::Resource.new('http://protected/resource', 'user', 'pass')
	#   resource.delete
	#
	class Resource
		attr_reader :url, :user, :password

		def initialize(url, user=nil, password=nil)
			@url = url
			@user = user
			@password = password
		end

		def get(headers={})
			Request.execute(:method => :get,
				:url => url,
				:user => user,
				:password => password,
				:headers => headers)
		end

		def post(payload, headers={})
			Request.execute(:method => :post,
				:url => url,
				:payload => payload,
				:user => user,
				:password => password,
				:headers => headers)
		end

		def put(payload, headers={})
			Request.execute(:method => :put,
				:url => url,
				:payload => payload,
				:user => user,
				:password => password,
				:headers => headers)
		end

		def delete(headers={})
			Request.execute(:method => :delete,
				:url => url,
				:user => user,
				:password => password,
				:headers => headers)
		end
	end
end
