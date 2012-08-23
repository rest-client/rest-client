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
  #   resource = RestClient::Resource.new('http://protected/resource', :user => 'user', :password => 'password')
  #   resource.delete
  #
  # With a timeout (seconds):
  #
  #   RestClient::Resource.new('http://slow', :read_timeout => 10)
  #
  # With an open timeout (seconds):
  #
  #   RestClient::Resource.new('http://behindfirewall', :open_timeout => 10)
  #
  # You can also use resources to share common headers. For headers keys,
  # symbols are converted to strings. Example:
  #
  #   resource = RestClient::Resource.new('http://some/resource', :headers => { :client_version => 1 })
  #
  # This header will be transported as X-Client-Version (notice the X prefix,
  # capitalization and hyphens)
  #
  # Use the [] syntax to allocate subresources:
  #
  #   site = RestClient::Resource.new('http://example.com', :user => 'adam', :password => 'mypasswd')
  #   site['posts/1/comments'].post 'Good article.', :content_type => 'text/plain'
  #
  class Resource
    attr_reader :url, :options, :block, :before_execution_procs

    def initialize(url, options={}, backwards_compatibility=nil, &block)
      @url = url
      @block = block
      if options.class == Hash
        @options = options
      else # compatibility with previous versions
        @options = { :user => options, :password => backwards_compatibility }
      end
      @before_execution_procs = []
    end

    def add_before_execution_proc( & block )
      @before_execution_procs << block
    end

    def reset_before_execution_procs
      @before_execution_procs = []
    end

    def get(additional_headers={}, &block)
      headers = (options[:headers] || {}).merge(additional_headers)
      args = options.merge(
              :method => :get,
              :url => url,
              :headers => headers)
      make_request(args, &(block || @block))
    end

    def head(additional_headers={}, &block)
      headers = (options[:headers] || {}).merge(additional_headers)
      args = options.merge(
              :method => :head,
              :url => url,
              :headers => headers)
      make_request(args, &(block || @block))
    end

    def post(payload, additional_headers={}, &block)
      headers = (options[:headers] || {}).merge(additional_headers)
      args = options.merge(
              :method => :post,
              :url => url,
              :payload => payload,
              :headers => headers)
      make_request(args, &(block || @block))
    end

    def put(payload, additional_headers={}, &block)
      headers = (options[:headers] || {}).merge(additional_headers)
      args = options.merge(
              :method => :put,
              :url => url,
              :payload => payload,
              :headers => headers)
      make_request(args, &(block || @block))
    end

    def patch(payload, additional_headers={}, &block)
      headers = (options[:headers] || {}).merge(additional_headers)
      args = options.merge(
              :method => :patch,
              :url => url,
              :payload => payload,
              :headers => headers)
      make_request(args, &(block || @block))
    end

    def delete(additional_headers={}, &block)
      headers = (options[:headers] || {}).merge(additional_headers)
      args = options.merge(
              :method => :delete,
              :url => url,
              :headers => headers)
      make_request(args, &(block || @block))
    end

    def to_s
      url
    end

    def user
      options[:user]
    end

    def password
      options[:password]
    end

    def headers
      options[:headers] || {}
    end

    def read_timeout
      options[:read_timeout]
    end

    def open_timeout
      options[:open_timeout]
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
    def [](suburl, &new_block)
      case
      when block_given? then self.class.new(concat_urls(url, suburl), options, &new_block)
      when block        then self.class.new(concat_urls(url, suburl), options, &block)
      else                   self.class.new(concat_urls(url, suburl), options)
      end
    end

    def concat_urls(url, suburl) # :nodoc:
      url = url.to_s
      suburl = suburl.to_s
      if url.slice(-1, 1) == '/' or suburl.slice(0, 1) == '/'
        url + suburl
      else
        "#{url}/#{suburl}"
      end
    end

    private

    def make_request(args, &block)
      request = Request.new(args)
      @before_execution_procs.each do |before_proc|
         request.add_before_execution_proc &before_proc
      end
      request.execute( &block )
    end

  end
end
