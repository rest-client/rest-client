require "stringio"
require "forwardable"

module Helpers
  def response_double(opts={})
    double('response', {:to_hash => {}}.merge(opts))
  end

  def fake_stderr
    original_stderr = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original_stderr
  end
end

class FakeIO
  def initialize(content)
    @io = StringIO.new(content)
  end

  extend Forwardable
  delegate [:read, :size, :rewind, :eof?, :close] => :@io
end
