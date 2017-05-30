require 'net/http'
require 'openssl'
require 'stringio'
require 'uri'

require File.dirname(__FILE__) + '/restclient/version'
require File.dirname(__FILE__) + '/restclient/platform'
require File.dirname(__FILE__) + '/restclient/exceptions'
require File.dirname(__FILE__) + '/restclient/utils'
require File.dirname(__FILE__) + '/restclient/request'
require File.dirname(__FILE__) + '/restclient/abstract_response'
require File.dirname(__FILE__) + '/restclient/response'
require File.dirname(__FILE__) + '/restclient/raw_response'
require File.dirname(__FILE__) + '/restclient/resource'
require File.dirname(__FILE__) + '/restclient/params_array'
require File.dirname(__FILE__) + '/restclient/payload'
require File.dirname(__FILE__) + '/restclient/windows'

# This module's static methods are the entry point for using the REST client.
#
# These helpers provide a concise way to issue simple requests with headers. If
# you need to set other options on a request (e.g. timeout, SSL options, etc.)
# then use {RestClient::Request.execute}, which supports all of these options.
#
# The {.get}, {.head}, {.delete}, and {.options} methods take a URL String and
# optional HTTP headers Hash.
#
# The {.post}, {.put}, and {.patch} methods take a URL String, a payload, and
# an optional HTTP headers Hash.
#
# All of these helpers are just thin wrappers around
# {RestClient::Request.execute RestClient::Request.execute}.
#
#
# ```ruby
# # Simple GET request, potentially with headers.
# RestClient.get('http://example.com/')
# # => <RestClient::Response 200 "<!doctype h...">
#
# RestClient.get('http://example.com/resource', accept: 'image/jpg')
#
# RestClient.get('http://example.com', 'If-Modified-Since': 'Sat, 10 Aug 2013 10:23:00 GMT')
# # raises RestClient::NotModified: 304 Not Modified
#
# # Basic authentication and SSL
# RestClient.get 'https://user:password@example.com/private/resource'
#
# # POST or PUT with a hash sends parameters as a urlencoded form body
# RestClient.post 'http://example.com/resource', :param1 => 'one'
#
# # nest hash parameters
# RestClient.post 'http://example.com/resource', :nested => { :param1 => 'one' }
#
# # POST and PUT with raw payloads
# RestClient.post 'http://example.com/resource', 'the post body', :content_type => 'text/plain'
# RestClient.post 'http://example.com/resource.xml', xml_doc
# RestClient.put 'http://example.com/resource.pdf', File.read('my.pdf'), :content_type => 'application/pdf'
#
# # DELETE
# RestClient.delete 'http://example.com/resource'
#
# # Retrieve the response http code and headers
# res = RestClient.get 'http://example.com/some.jpg'
# res.code                    # => 200
# res.headers[:content_type]  # => 'image/jpg'
#
# # HEAD
# RestClient.head('http://example.com').headers
# ```
#
# To use with a proxy, just set RestClient.proxy to the proper http proxy:
#
#     RestClient.proxy = "http://proxy.example.com/"
#
# Proxies can also be set via the `http_proxy`/`https_proxy` environment
# variables, or with the `:proxy` option on an individual {RestClient::Request}.
#
# For live tests of RestClient, try using https://httpbin.org/. This service
# echoes back information about the HTTP request.
#
#     r =  RestClient.post('https://httpbin.org/post', foo: 'bar')
#     # => <RestClient::Response 200 "{\n  \"args\":...">
#     puts r.body
#     {
#       "args": {},
#       "data": "",
#       "files": {},
#       "form": {
#         "foo": "bar"
#       },
#       "headers": {
#         "Accept": "*/*",
#         "Accept-Encoding": "gzip;q=1.0,deflate;q=0.6,identity;q=0.3",
#         "Connection": "close",
#         "Content-Length": "7",
#         "Content-Type": "application/x-www-form-urlencoded",
#         "Host": "httpbin.org",
#         "User-Agent": "rest-client/2.1.0 (linux-gnu x86_64) ruby/2.3.3p222"
#       },
#       "json": null,
#       "url": "https://httpbin.org/post"
#     }
#
module RestClient

  def self.get(url, headers={}, &block)
    Request.execute(:method => :get, :url => url, :headers => headers, &block)
  end

  def self.post(url, payload, headers={}, &block)
    Request.execute(:method => :post, :url => url, :payload => payload, :headers => headers, &block)
  end

  def self.patch(url, payload, headers={}, &block)
    Request.execute(:method => :patch, :url => url, :payload => payload, :headers => headers, &block)
  end

  def self.put(url, payload, headers={}, &block)
    Request.execute(:method => :put, :url => url, :payload => payload, :headers => headers, &block)
  end

  def self.delete(url, headers={}, &block)
    Request.execute(:method => :delete, :url => url, :headers => headers, &block)
  end

  def self.head(url, headers={}, &block)
    Request.execute(:method => :head, :url => url, :headers => headers, &block)
  end

  def self.options(url, headers={}, &block)
    Request.execute(:method => :options, :url => url, :headers => headers, &block)
  end

  # A global proxy URL to use for all requests. This can be overridden on a
  # per-request basis by passing `:proxy` to RestClient::Request.
  def self.proxy
    @proxy ||= nil
  end

  # Set a proxy URL to use for all requests.
  #
  # @param value [String] The proxy URL.
  #
  def self.proxy=(value)
    @proxy = value
    @proxy_set = true
  end

  # Return whether RestClient.proxy was set explicitly. We use this to
  # differentiate between no value being set and a value explicitly set to nil.
  #
  # @return [Boolean]
  #
  def self.proxy_set?
    @proxy_set ||= false
  end

  # Setup the log for RestClient calls.
  # Value should be a logger but can can be stdout, stderr, or a filename.
  # You can also configure logging by the environment variable RESTCLIENT_LOG.
  #
  # @param log [Logger, #<<, String] The log to write to. See {.create_log}
  #
  def self.log= log
    @@log = create_log log
  end

  # Create a log that responds to `<<` like a Logger.
  #
  # @param param [Logger, #<<, String, nil] The log to write to. Should be a
  #   Logger, IO, or other object with a `<<` method. If param is a String, it
  #   will be treated as a filename and that file will be opened as a log file.
  #   The special Strings `"stdout"` and `"stderr"` will log to `STDOUT` and
  #   `STDERR`.
  #
  def self.create_log param
    if param
      if param.is_a? String
        if param == 'stdout'
          stdout_logger = Class.new do
            def << obj
              STDOUT.puts obj
            end
          end
          stdout_logger.new
        elsif param == 'stderr'
          stderr_logger = Class.new do
            def << obj
              STDERR.puts obj
            end
          end
          stderr_logger.new
        else
          file_logger = Class.new do
            attr_writer :target_file

            def << obj
              File.open(@target_file, 'a') { |f| f.puts obj }
            end
          end
          logger = file_logger.new
          logger.target_file = param
          logger
        end
      else
        param
      end
    end
  end

  @@env_log = create_log ENV['RESTCLIENT_LOG']

  @@log = nil

  # The RestClient global logger. This will be used for all requests unless a
  # `:log` option is set on the individual request.
  #
  # @see log=
  #
  def self.log
    @@env_log || @@log
  end

  # Array of procs executed prior to each request.
  @@before_execution_procs = []

  # Add a Proc to be called before each request in executed.
  # The proc parameters will be the http request and the request params.
  def self.add_before_execution_proc &proc
    raise ArgumentError.new('block is required') unless proc
    @@before_execution_procs << proc
  end

  # Reset the procs to be called before each request is executed.
  def self.reset_before_execution_procs
    @@before_execution_procs = []
  end

  # Array of procs executed prior to each request.
  def self.before_execution_procs
    @@before_execution_procs
  end

end
