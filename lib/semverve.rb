# frozen_string_literal: true

require_relative "semverve/finding"
require_relative "semverve/fix_result"
require_relative "semverve/version_literal_rewriter"
require_relative "semverve/version_match_policy"
require_relative "semverve/configuration"
require_relative "semverve/version"

##
# Namespace for Semverve configuration and version-file Rake tasks.
module Semverve
  class << self
    ##
    # Yields the global configuration object for customization.
    #
    # @yieldparam [Semverve::Configuration] configuration
    #
    # @return [Semverve::Configuration]
    def configure
      yield configuration
    end

    ##
    # Returns the global mutable configuration object.
    #
    # @return [Semverve::Configuration]
    def configuration
      @configuration ||= Configuration.new
    end
  end
end

require_relative "semverve/version_audit"
require_relative "semverve/railtie" if defined?(::Rails::Railtie)
