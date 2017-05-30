require 'rbconfig'

module RestClient
  module Platform
    # Return true if we are running on a darwin-based Ruby platform. This will
    # be false for jruby even on OS X.
    #
    # @return [Boolean]
    def self.mac_mri?
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
      # defined on mri >= 1.9
      RUBY_ENGINE == 'jruby'
    end

    # Return the host architecture and CPU from `RbConfig::CONFIG`.
    #
    # @return [String]
    def self.architecture
      "#{RbConfig::CONFIG['host_os']} #{RbConfig::CONFIG['host_cpu']}"
    end

    # Return information about the ruby version from `RUBY_ENGINE`,
    # `RUBY_VERSION`, and `RUBY_PATCHLEVEL`.
    #
    # When running in jruby, also return the jruby version.
    #
    # @return [String]
    #
    def self.ruby_agent_version
      case RUBY_ENGINE
      when 'jruby'
        "jruby/#{JRUBY_VERSION} (#{RUBY_VERSION}p#{RUBY_PATCHLEVEL})"
      else
        "#{RUBY_ENGINE}/#{RUBY_VERSION}p#{RUBY_PATCHLEVEL}"
      end
    end

    # Return a reasonable string for the `User-Agent` HTTP header.
    #
    # @example
    #   "rest-client/2.1.0 (linux-gnu x86_64) ruby/2.3.3p222"
    #
    # @return [String]
    #
    # @see VERSION RestClient::VERSION
    # @see .architecture
    # @see .ruby_agent_version
    #
    def self.default_user_agent
      "rest-client/#{VERSION} (#{architecture}) #{ruby_agent_version}"
    end
  end
end
