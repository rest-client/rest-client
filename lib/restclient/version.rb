module RestClient
  VERSION = '1.7.0.alpha' unless defined?(self::VERSION)

  def self.version
    VERSION
  end
end
