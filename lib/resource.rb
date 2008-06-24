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
	# Use the [] syntax to allocate subresources:
	#
	#   site = RestClient::Resource.new('http://example.com', 'adam', 'mypasswd')
	#   site['posts/1/comments'].post 'Good article.', :content_type => 'text/plain'
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

		# Construct a subresource, preserving authentication.
		#
		# Example:
		#
		#   site = RestClient::Resource.new('http://example.com', 'adam', 'mypasswd')
		#   site['posts/1/comments'].post 'Good article.', :content_type => 'text/plain'
		#
		# This is especially useful if you wish to define your site in one place and
		# call it in multiple locations:
		#
		#   def orders
		#     RestClient::Resource.new('http://example.com/orders', 'admin', 'mypasswd')
		#   end
		#
		#   orders.get                     # GET http://example.com/orders
		#   orders['1'].get                # GET http://example.com/orders/1
		#   orders['1/items'].delete       # DELETE http://example.com/orders/1/items
		#
		# Nest resources as far as you want:
		#
		#   site = RestClient::Resource.new('http://example.com')
		#   posts = site['posts']
		#   first_post = posts['1']
		#   comments = first_post['comments']
		#   comments.post 'Hello', :content_type => 'text/plain'
		#
		def [](suburl)
			self.class.new(concat_urls(url, suburl), user, password)
		end

		def concat_urls(url, suburl)   # :nodoc:
			url = url.to_s
			suburl = suburl.to_s
			if url.slice(-1, 1) == '/' or suburl.slice(0, 1) == '/'
				url + suburl
			else
				"#{url}/#{suburl}"
			end
		end
	end
end
