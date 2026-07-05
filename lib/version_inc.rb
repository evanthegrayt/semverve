# frozen_string_literal: true

require_relative "version_inc/configuration"
require_relative "version_inc/version"

module VersionInc
  class << self
    def configure
      yield configuration
    end

    def configuration
      @configuration ||= Configuration.new
    end
  end
end
