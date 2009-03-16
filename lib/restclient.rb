require 'uri'
require 'net/https'
require 'zlib'
require 'stringio'

require File.dirname(__FILE__) + '/restclient/request'
require File.dirname(__FILE__) + '/restclient/mixin/response'
require File.dirname(__FILE__) + '/restclient/response'
require File.dirname(__FILE__) + '/restclient/raw_response'
require File.dirname(__FILE__) + '/restclient/resource'
require File.dirname(__FILE__) + '/restclient/exceptions'

# This module's static methods are the entry point for using the REST client.
#
#   # GET
#   xml = RestClient.get 'http://example.com/resource'
#   jpg = RestClient.get 'http://example.com/resource', :accept => 'image/jpg'
#
#   # authentication and SSL
#   RestClient.get 'https://user:password@example.com/private/resource'
#
#   # POST or PUT with a hash sends parameters as a urlencoded form body
#   RestClient.post 'http://example.com/resource', :param1 => 'one'
#
#   # nest hash parameters
#   RestClient.post 'http://example.com/resource', :nested => { :param1 => 'one' }
#
#   # POST and PUT with raw payloads
#   RestClient.post 'http://example.com/resource', 'the post body', :content_type => 'text/plain'
#   RestClient.post 'http://example.com/resource.xml', xml_doc
#   RestClient.put 'http://example.com/resource.pdf', File.read('my.pdf'), :content_type => 'application/pdf'
#
#   # DELETE
#   RestClient.delete 'http://example.com/resource'
#
#   # retreive the response http code and headers
#   res = RestClient.get 'http://example.com/some.jpg'
#   res.code                    # => 200
#   res.headers[:content_type]  # => 'image/jpg'
#
#   # HEAD
#   RestClient.head('http://example.com').headers
#
# To use with a proxy, just set RestClient.proxy to the proper http proxy:
#
#   RestClient.proxy = "http://proxy.example.com/"
#
# Or inherit the proxy from the environment:
#
#   RestClient.proxy = ENV['http_proxy']
#
# For live tests of RestClient, try using http://rest-test.heroku.com, which echoes back information about the rest call:
#
#   >> RestClient.put 'http://rest-test.heroku.com/resource', :foo => 'baz'
#   => "PUT http://rest-test.heroku.com/resource with a 7 byte payload, content type application/x-www-form-urlencoded {\"foo\"=>\"baz\"}"
#
module RestClient
	def self.get(url, headers={})
		Request.execute(:method => :get, :url => url, :headers => headers)
	end

	def self.post(url, payload, headers={})
		Request.execute(:method => :post, :url => url, :payload => payload, :headers => headers)
	end

	def self.put(url, payload, headers={})
		Request.execute(:method => :put, :url => url, :payload => payload, :headers => headers)
	end

	def self.delete(url, headers={})
		Request.execute(:method => :delete, :url => url, :headers => headers)
	end

	def self.head(url, headers={})
		Request.execute(:method => :head, :url => url, :headers => headers)
	end

	class << self
		attr_accessor :proxy
	end

	# Print log of RestClient calls.  Value can be stdout, stderr, or a filename.
	# You can also configure logging by the environment variable RESTCLIENT_LOG.
	def self.log=(log)
		@@log = log
	end

	def self.log    # :nodoc:
		return ENV['RESTCLIENT_LOG'] if ENV['RESTCLIENT_LOG']
		return @@log if defined? @@log
		nil
	end
end
