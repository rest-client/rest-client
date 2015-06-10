module RestClient
  VERSION = '1.6.9' unless defined?(self::VERSION)

  def self.version
    VERSION
  end
end
