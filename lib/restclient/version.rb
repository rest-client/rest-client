module RestClient
  VERSION = '2.0.0.alpha' unless defined?(self::VERSION)

  def self.version
    VERSION
  end
end
