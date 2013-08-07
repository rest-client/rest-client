module RestClient
  VERSION = '1.6.8.alpha' unless defined?(self::VERSION)

  def self.version
    VERSION
  end
end
