module RestClient

  # Utility methods intended for use only within RestClient
  #
  # @api private

  module Util
    private

    def parser
      URI.const_defined?(:Parser) ? URI::Parser.new : URI
    end

  end
end
