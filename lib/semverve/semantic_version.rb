# frozen_string_literal: true

require_relative "error"

module Semverve
  ##
  # Value object for a MAJOR.MINOR.PATCH semantic version.
  class SemanticVersion
    ##
    # Regular expression for Semverve's supported version format.
    #
    # @return [Regexp]
    PATTERN = /\A(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)\z/

    ##
    # Major version number.
    #
    # @return [Integer]
    attr_reader :major

    ##
    # Minor version number.
    #
    # @return [Integer]
    attr_reader :minor

    ##
    # Patch version number.
    #
    # @return [Integer]
    attr_reader :patch

    ##
    # Parses a value into a semantic version.
    #
    # @param [#to_s] value
    #
    # @return [Semverve::SemanticVersion]
    def self.parse(value)
      match = value.to_s.match(PATTERN)

      unless match
        raise Error, "Expected a semantic version in MAJOR.MINOR.PATCH format, got #{value.inspect}."
      end

      new(
        major: match[:major].to_i,
        minor: match[:minor].to_i,
        patch: match[:patch].to_i
      )
    end

    ##
    # Initializes a semantic version.
    #
    # @param [Integer] major
    # @param [Integer] minor
    # @param [Integer] patch
    #
    # @return [Semverve::SemanticVersion]
    def initialize(major:, minor:, patch:)
      @major = major
      @minor = minor
      @patch = patch
    end

    ##
    # Returns a new semantic version with the requested level incremented.
    #
    # @param [Symbol, String] level
    #
    # @return [Semverve::SemanticVersion]
    def increment(level)
      case level.to_sym
      when :major
        self.class.new(major: major + 1, minor: 0, patch: 0)
      when :minor
        self.class.new(major: major, minor: minor + 1, patch: 0)
      when :patch
        self.class.new(major: major, minor: minor, patch: patch + 1)
      else
        raise Error, "Unknown version increment level: #{level.inspect}."
      end
    end

    ##
    # Version as +MAJOR.MINOR.PATCH+.
    #
    # @return [String]
    def to_s
      [major, minor, patch].join(".")
    end
  end
end
