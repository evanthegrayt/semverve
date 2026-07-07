# frozen_string_literal: true

require_relative "error"

module Semverve
  ##
  # Decides whether a discovered version should be reported or fixed.
  class VersionMatchPolicy
    ##
    # Initializes a version match policy.
    #
    # @param [Semverve::SemanticVersion] current_version
    # @param [Symbol, String] match_mode
    # @param [Semverve::SemanticVersion, nil] target_version
    #
    # @return [Semverve::VersionMatchPolicy]
    def initialize(current_version:, match_mode:, target_version: nil)
      @current_version = current_version
      @match_mode = match_mode.to_sym
      @target_version = target_version
    end

    ##
    # Whether the version should be reported or fixed.
    #
    # @param [Semverve::SemanticVersion] version
    #
    # @return [Boolean]
    def report?(version)
      return version == target_version if target_version

      case match_mode
      when :older
        version < current_version
      when :non_current
        version != current_version
      else
        raise Error, "Unknown version match mode #{match_mode.inspect}. Use :older or :non_current."
      end
    end

    private

    ##
    # Current Semverve version.
    #
    # @return [Semverve::SemanticVersion]
    attr_reader :current_version

    ##
    # Matching mode when no exact target version is supplied.
    #
    # @return [Symbol]
    attr_reader :match_mode

    ##
    # Exact version to match.
    #
    # @return [Semverve::SemanticVersion, nil]
    attr_reader :target_version
  end
end
