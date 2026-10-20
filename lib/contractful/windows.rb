# frozen_string_literal: true

module Contractful
  # Windows-specific support code (root certificate store loading).
  module Windows
  end
end

require_relative 'windows/root_certs' if Contractful::Platform.windows?
