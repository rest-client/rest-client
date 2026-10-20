# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'stringio'
require 'uri'
require 'json'

require File.dirname(__FILE__) + '/contractful/version'
require File.dirname(__FILE__) + '/contractful/platform'
require File.dirname(__FILE__) + '/contractful/exceptions'
require File.dirname(__FILE__) + '/contractful/notifications'
require File.dirname(__FILE__) + '/contractful/circuit_breaker'
require File.dirname(__FILE__) + '/contractful/pacer'
require File.dirname(__FILE__) + '/contractful/utils'
require File.dirname(__FILE__) + '/contractful/request'
require File.dirname(__FILE__) + '/contractful/connection_pool'
require File.dirname(__FILE__) + '/contractful/abstract_response'
require File.dirname(__FILE__) + '/contractful/rate_limit'
require File.dirname(__FILE__) + '/contractful/response'
require File.dirname(__FILE__) + '/contractful/raw_response'
require File.dirname(__FILE__) + '/contractful/resource'
require File.dirname(__FILE__) + '/contractful/params_array'
require File.dirname(__FILE__) + '/contractful/payload'
require File.dirname(__FILE__) + '/contractful/contract'
require File.dirname(__FILE__) + '/contractful/windows'

# Contractful is a contract-first HTTP client for Ruby.
#
# Two layers share one request pipeline:
#
# * {Contractful} (this module) — the raw HTTP facade: one-liner verb
#   methods ({Contractful.get}, {Contractful.post}, ...) returning a
#   String-like {Contractful::Response}, with automatic retries, persistent
#   connections, proxies, redirects, cookies and a retryable-vs-terminal
#   error classification ({Contractful::Exceptions}).
# * {Contractful::Contract} — the contract-first layer: declare verb, path,
#   typed parameters and expected responses, and client methods, path
#   builders, validation and introspection are generated for you. See the
#   "Contract-first API clients" section of the README.
#
# @example Raw HTTP
#   Contractful.get('https://api.example.com/users', accept: 'application/json')
#   Contractful.post('https://api.example.com/users', name: 'Ada')   # form body
#
# @example Contract-first client
#   class Client
#     include Contractful::Contract
#     base 'https://api.example.com'
#     contract :list_users, 'GET /users' do
#       param :page, Integer, default: 1
#       responds 200, type: :array
#     end
#   end
#
# @see file:README.md Project overview and usage
# @see file:API.md Normative public API reference
# @see Contractful::Request The underlying request pipeline
#
# This module's static methods are the entry point for using the REST client.
#
#   # GET
#   xml = Contractful.get 'http://example.com/resource'
#   jpg = Contractful.get 'http://example.com/resource', :accept => 'image/jpg'
#
#   # authentication and SSL
#   Contractful.get 'https://user:password@example.com/private/resource'
#
#   # POST or PUT with a hash sends parameters as a urlencoded form body
#   Contractful.post 'http://example.com/resource', :param1 => 'one'
#
#   # nest hash parameters
#   Contractful.post 'http://example.com/resource', :nested => { :param1 => 'one' }
#
#   # POST and PUT with raw payloads
#   Contractful.post 'http://example.com/resource', 'the post body', :content_type => 'text/plain'
#   Contractful.post 'http://example.com/resource.xml', xml_doc
#   Contractful.put 'http://example.com/resource.pdf', File.read('my.pdf'), :content_type => 'application/pdf'
#
#   # DELETE
#   Contractful.delete 'http://example.com/resource'
#
#   # retrieve the response http code and headers
#   res = Contractful.get 'http://example.com/some.jpg'
#   res.code                    # => 200
#   res.headers[:content_type]  # => 'image/jpg'
#
#   # HEAD
#   Contractful.head('http://example.com').headers
#
# The module helpers accept a headers Hash only. Transport and resilience
# options (timeouts, retries, breaker:, pace:, persistent:, ...) belong to
# Contractful::Request.execute:
#
#   Contractful::Request.execute(method: :get, url: 'http://example.com', max_retries: 3)
#
# To use with a proxy, just set Contractful.proxy to the proper http proxy:
#
#   Contractful.proxy = "http://proxy.example.com/"
#
# Or inherit the proxy from the environment:
#
#   Contractful.proxy = ENV['http_proxy']
#
# For live tests of Contractful, try using http://rest-test.heroku.com, which echoes back information about the rest call:
#
#   >> Contractful.put 'http://rest-test.heroku.com/resource', :foo => 'baz'
#   => "PUT http://rest-test.heroku.com/resource with a 7 byte payload, content type application/x-www-form-urlencoded {\"foo\"=>\"baz\"}"
#
module Contractful
  def self.get(url, headers = {}, &block)
    Request.execute(method: :get, url: url, headers: headers, &block)
  end

  def self.post(url, payload, headers = {}, &block)
    Request.execute(method: :post, url: url, payload: payload, headers: headers, &block)
  end

  def self.patch(url, payload, headers = {}, &block)
    Request.execute(method: :patch, url: url, payload: payload, headers: headers, &block)
  end

  def self.put(url, payload, headers = {}, &block)
    Request.execute(method: :put, url: url, payload: payload, headers: headers, &block)
  end

  def self.delete(url, headers = {}, &block)
    Request.execute(method: :delete, url: url, headers: headers, &block)
  end

  def self.head(url, headers = {}, &block)
    Request.execute(method: :head, url: url, headers: headers, &block)
  end

  def self.options(url, headers = {}, &block)
    Request.execute(method: :options, url: url, headers: headers, &block)
  end

  # A global proxy URL to use for all requests. This can be overridden on a
  # per-request basis by passing `:proxy` to Contractful::Request.
  def self.proxy
    @proxy ||= nil
  end

  def self.proxy=(value)
    @proxy = value
    @proxy_set = true
  end

  # Return whether Contractful.proxy was set explicitly. We use this to
  # differentiate between no value being set and a value explicitly set to nil.
  #
  # @return [Boolean]
  #
  def self.proxy_set?
    @proxy_set ||= false
  end

  # Setup the log for Contractful calls.
  # Value should be a logger but can can be stdout, stderr, or a filename.
  # You can also configure logging by the environment variable CONTRACTFUL_LOG.
  def self.log= log
    @@log = create_log log
  end

  # Create a log that respond to << like a logger
  # param can be 'stdout', 'stderr', a string (then we will log to that file) or a logger (then we return it)
  def self.create_log param
    return unless param

    if param.is_a? String
      if param == 'stdout'
        stdout_logger = Class.new do
          def << obj
            # $stdout rather than the STDOUT constant so that logging
            # follows a reassigned $stdout (matching the stderr logger's
            # use of Kernel#warn, which writes to the current $stderr).
            $stdout.puts obj
          end
        end
        stdout_logger.new
      elsif param == 'stderr'
        stderr_logger = Class.new do
          def << obj
            warn obj
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

  @@env_log = create_log ENV['CONTRACTFUL_LOG']

  @@log = nil

  def self.log # :nodoc:
    @@env_log || @@log
  end

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

  def self.before_execution_procs # :nodoc:
    @@before_execution_procs
  end
end
