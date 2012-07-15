$: << 'lib'

require 'bundler/setup'

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
