module RestClient2
  module Windows
  end
end

if RestClient2::Platform.windows?
  require_relative './windows/root_certs'
end
