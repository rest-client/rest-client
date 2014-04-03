module RestClient
  module Platform
    def self.mac?
      RUBY_PLATFORM.include?('darwin')
    end
  end
end
