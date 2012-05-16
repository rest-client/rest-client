def is_ruby_19?
  RUBY_VERSION == '1.9.1' or RUBY_VERSION == '1.9.2'
end

require 'rubygems'
require 'spec'

begin
  require "ruby-debug"
rescue LoadError
  # NOP, ignore
end

require File.dirname(__FILE__) + '/../lib/restclient'
require File.join(File.dirname(__FILE__), 'helpers', 'file_content_helper')
