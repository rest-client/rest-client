# frozen_string_literal: true

# Gem version constants for contractful.
module Contractful
  VERSION_INFO = [0, 1, 0].freeze
  VERSION = VERSION_INFO.map(&:to_s).join('.').freeze

  def self.version
    VERSION
  end
end
