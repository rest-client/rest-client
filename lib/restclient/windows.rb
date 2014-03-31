module RestClient
  module Windows
    def self.windows?
      # Ruby only sets File::ALT_SEPARATOR on Windows, and the Ruby standard
      # library uses that to test what platform it's on.
      !!File::ALT_SEPARATOR
    end
  end
end

if RestClient::Windows.windows?
  require_relative './windows/root_certs'
end
