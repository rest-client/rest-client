module Helpers
  def response_double(opts={})
    double('response', {:to_hash => {}}.merge(opts))
  end
end
