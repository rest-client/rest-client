def is_ruby_19?
  RUBY_VERSION > '1.9'
end

require 'rubygems'

begin
  require "ruby-debug"
rescue LoadError
  # NOP, ignore
end

require File.dirname(__FILE__) + '/../lib/restclient'
