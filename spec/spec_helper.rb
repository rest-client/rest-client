def is_ruby_19?
  RUBY_VERSION > '1.9'
end

begin
  require "ruby-debug"
rescue LoadError
  # NOP, ignore
end

require 'webmock/rspec'
require 'restclient'
