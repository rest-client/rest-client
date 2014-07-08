module RestClient
  VERSION = '1.6.8' unless defined?(self::VERSION)

  def self.version
    VERSION
  end
end
