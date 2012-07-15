$: << 'lib'

require 'bundler/setup'

# Code coverage for Ruby 1.9+
if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start
end

require 'rspec'
require 'webmock'
require 'webmock/rspec'

#begin
  #require "ruby-debug"
#rescue LoadError
  ## NOP, ignore
#end

def is_ruby_19?
  RUBY_VERSION =~ /^1\.9/
end

require File.dirname(__FILE__) + '/../lib/restclient'
