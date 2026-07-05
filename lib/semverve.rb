# frozen_string_literal: true

require_relative "semverve/configuration"
require_relative "semverve/version"

module Semverve
  class << self
    def configure
      yield configuration
    end

    def configuration
      @configuration ||= Configuration.new
    end
  end
end
