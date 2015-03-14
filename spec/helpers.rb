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
