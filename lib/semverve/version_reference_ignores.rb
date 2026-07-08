# frozen_string_literal: true

module Semverve
  ##
  # Answers whether a project-relative file/line/version finding is configured
  # as ignored.
  class VersionReferenceIgnores
    ##
    # Initializes configured version-reference ignores.
    #
    # @param [Hash] ignores
    #
    # @return [Semverve::VersionReferenceIgnores]
    def initialize(ignores)
      @ignores = ignores || {}
    end

    ##
    # Whether the reference should be ignored.
    #
    # @param [String] path
    # @param [Integer] line
    # @param [Semverve::SemanticVersion, String] version
    #
    # @return [Boolean]
    def ignored?(path:, line:, version:)
      versions = versions_for(path, line)

      Array(versions).map(&:to_s).include?(version.to_s)
    end

    private

    ##
    # Configured ignores.
    #
    # @return [Hash]
    attr_reader :ignores

    ##
    # Configured versions for a project-relative path and one-based line.
    #
    # @param [String] path
    # @param [Integer] line
    #
    # @return [Array<String>, String, nil]
    def versions_for(path, line)
      line_ignores = ignores[path.to_s]
      return unless line_ignores.respond_to?(:[])

      line_ignores[line] || line_ignores[line.to_s]
    end
  end
end
