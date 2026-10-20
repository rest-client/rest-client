# frozen_string_literal: true

module Contractful
  # A class that can be instantiated for access to a RESTful resource,
  # including authentication.
  #
  # Example:
  #
  #   resource = Contractful::Resource.new('http://some/resource')
  #   jpg = resource.get(:accept => 'image/jpg')
  #
  # With HTTP basic authentication:
  #
  #   resource = Contractful::Resource.new('http://protected/resource', :user => 'user', :password => 'password')
  #   resource.delete
  #
  # With a timeout (seconds):
  #
  #   Contractful::Resource.new('http://slow', :read_timeout => 10)
  #
  # With an open timeout (seconds):
  #
  #   Contractful::Resource.new('http://behindfirewall', :open_timeout => 10)
  #
  # You can also use resources to share common headers. For headers keys,
  # symbols are converted to strings. Example:
  #
  #   resource = Contractful::Resource.new('http://some/resource', :headers => { :client_version => 1 })
  #
  # This header will be transported as Client-Version (symbol keys are split
  # on underscores and capitalized; no X- prefix is added)
  #
  # Use the [] syntax to allocate subresources:
  #
  #   site = Contractful::Resource.new('http://example.com', :user => 'adam', :password => 'mypasswd')
  #   site['posts/1/comments'].post 'Good article.', :content_type => 'text/plain'
  #
  class Resource
    attr_reader :url, :options, :block

    def initialize(url, options = {}, backwards_compatibility = nil, &block)
      @url = url
      @block = block
      # compatibility with previous versions
      @options = if options.instance_of?(Hash)
                   options
                 else
                   { user: options, password: backwards_compatibility }
                 end
    end

    def get(additional_headers = {}, &block)
      headers = (options[:headers] || {}).merge(additional_headers)
      Request.execute(options.merge(
                        method: :get,
                        url: url,
                        headers: headers,
                        log: log
                      ), &block || @block)
    end

    def head(additional_headers = {}, &block)
      headers = (options[:headers] || {}).merge(additional_headers)
      Request.execute(options.merge(
                        method: :head,
                        url: url,
                        headers: headers,
                        log: log
                      ), &block || @block)
    end

    def post(payload, additional_headers = {}, &block)
      headers = (options[:headers] || {}).merge(additional_headers)
      Request.execute(options.merge(
                        method: :post,
                        url: url,
                        payload: payload,
                        headers: headers,
                        log: log
                      ), &block || @block)
    end

    def put(payload, additional_headers = {}, &block)
      headers = (options[:headers] || {}).merge(additional_headers)
      Request.execute(options.merge(
                        method: :put,
                        url: url,
                        payload: payload,
                        headers: headers,
                        log: log
                      ), &block || @block)
    end

    def patch(payload, additional_headers = {}, &block)
      headers = (options[:headers] || {}).merge(additional_headers)
      Request.execute(options.merge(
                        method: :patch,
                        url: url,
                        payload: payload,
                        headers: headers,
                        log: log
                      ), &block || @block)
    end

    def delete(additional_headers = {}, &block)
      headers = (options[:headers] || {}).merge(additional_headers)
      Request.execute(options.merge(
                        method: :delete,
                        url: url,
                        headers: headers,
                        log: log
                      ), &block || @block)
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

    def log
      options[:log] || Contractful.log
    end

    # Construct a subresource, preserving authentication.
    #
    # Example:
    #
    #   site = Contractful::Resource.new('http://example.com', 'adam', 'mypasswd')
    #   site['posts/1/comments'].post 'Good article.', :content_type => 'text/plain'
    #
    # This is especially useful if you wish to define your site in one place and
    # call it in multiple locations:
    #
    #   def orders
    #     Contractful::Resource.new('http://example.com/orders', 'admin', 'mypasswd')
    #   end
    #
    #   orders.get                     # GET http://example.com/orders
    #   orders['1'].get                # GET http://example.com/orders/1
    #   orders['1/items'].delete       # DELETE http://example.com/orders/1/items
    #
    # Nest resources as far as you want:
    #
    #   site = Contractful::Resource.new('http://example.com')
    #   posts = site['posts']
    #   first_post = posts['1']
    #   comments = first_post['comments']
    #   comments.post 'Hello', :content_type => 'text/plain'
    #
    def [](suburl, &new_block)
      if block_given?
        self.class.new(concat_urls(url, suburl), options, &new_block)
      elsif block
        self.class.new(concat_urls(url, suburl), options, &block)
      else
        self.class.new(concat_urls(url, suburl), options)
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
  end
end
