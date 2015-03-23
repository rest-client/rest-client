module RestClient
  VERSION = '1.8.0.rc1' unless defined?(self::VERSION)

  def self.version
    VERSION
  end
end
