module RestClient

  # The current RestClient version array
  VERSION_INFO = [2, 1, 0, 'rc1'] unless defined?(self::VERSION_INFO)

  # The current RestClient version string
  VERSION = VERSION_INFO.map(&:to_s).join('.') unless defined?(self::VERSION)

  # @return [String] The current RestClient version string
  def self.version
    VERSION
  end
end
