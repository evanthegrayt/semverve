# frozen_string_literal: true

require_relative "error"

module Semverve
  class SemanticVersion
    PATTERN = /\A(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)\z/

    attr_reader :major, :minor, :patch

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

    def initialize(major:, minor:, patch:)
      @major = major
      @minor = minor
      @patch = patch
    end

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

    def to_s
      [major, minor, patch].join(".")
    end
  end
end
