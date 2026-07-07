# frozen_string_literal: true

module Semverve
  ##
  # A version mismatch found by a Semverve check.
  class Finding
    ##
    # Path relative to the configured project root.
    #
    # @return [String]
    attr_reader :path

    ##
    # One-based line number.
    #
    # @return [Integer]
    attr_reader :line

    ##
    # One-based column number.
    #
    # @return [Integer]
    attr_reader :column

    ##
    # Referenced semantic version.
    #
    # @return [Semverve::SemanticVersion]
    attr_reader :version

    ##
    # Optional output label for findings that carry their own label.
    #
    # @return [String, nil]
    attr_reader :label

    ##
    # Initializes a finding.
    #
    # @param [String] path
    # @param [Integer] line
    # @param [Integer] column
    # @param [Semverve::SemanticVersion] version
    # @param [String, nil] label
    #
    # @return [Semverve::Finding]
    def initialize(path:, line:, column:, version:, label: nil)
      @path = path
      @line = line
      @column = column
      @version = version
      @label = label
    end
  end
end
