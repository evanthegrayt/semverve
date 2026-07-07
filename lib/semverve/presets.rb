# frozen_string_literal: true

require_relative "adapters"

module Semverve
  ##
  # Backward-compatible framework preset lookup.
  module Presets
    ##
    # Returns defaults for a configured preset.
    #
    # @param [Symbol, String, nil] name
    # @param [Semverve::Configuration] configuration
    #
    # @return [Hash]
    def self.defaults_for(name, configuration)
      Adapters.defaults_for(name, configuration)
    end

    ##
    # Returns a preset adapter.
    #
    # @param [Symbol, String] name
    #
    # @return [#name, #defaults]
    def self.fetch(name)
      Adapters.fetch(name)
    end
  end
end
