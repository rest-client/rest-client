module RestClient
  VERSION = '1.7.1' unless defined?(self::VERSION)

  def self.version
    VERSION
  end
end
