Encoding.default_internal = Encoding.default_external = "ASCII-8BIT" if RUBY_VERSION == '1.9.1' or RUBY_VERSION == '1.9.2'

require 'rubygems'
require 'spec'

begin
  require "ruby-debug"
rescue LoadError
  # NOP, ignore
end

require File.dirname(__FILE__) + '/../lib/restclient'
