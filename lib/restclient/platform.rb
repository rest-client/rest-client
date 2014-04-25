module RestClient
  module Platform
    # Return true if we are running on a darwin-based Ruby platform. This will
    # be false for jruby even on OS X.
    #
    # @return [Boolean]
    def self.mac?
      RUBY_PLATFORM.include?('darwin')
    end

    # Return true if we are running on Windows.
    #
    # @return [Boolean]
    #
    def self.windows?
      # Ruby only sets File::ALT_SEPARATOR on Windows, and the Ruby standard
      # library uses that to test what platform it's on.
      !!File::ALT_SEPARATOR
    end

    # Return true if we are running on jruby.
    #
    # @return [Boolean]
    #
    def self.jruby?
      RUBY_PLATFORM == 'java'
    end
  end
end
