# frozen_string_literal: true

require_relative "error"
require_relative "formats"

module Semverve
  ##
  # Reads and updates an existing version file.
  class VersionFile
    ##
    # Initializes a version-file reader and writer.
    #
    # @param [Semverve::ResolvedConfiguration] configuration
    #
    # @return [Semverve::VersionFile]
    def initialize(configuration)
      @configuration = configuration
      @format = Formats.fetch(configuration.format)
    end

    ##
    # Current semantic version parsed from the version file.
    #
    # @return [Semverve::SemanticVersion]
    def current
      format.parse(read, path: path)
    end

    ##
    # Increments one semantic-version level and writes the result.
    #
    # @param [Symbol, String] level
    #
    # @return [Semverve::SemanticVersion]
    def increment(level)
      next_version = current.increment(level)

      File.write(path, format.replace(read, next_version, path: path))
      next_version
    end

    private

    ##
    # Resolved configuration used to locate the version file.
    #
    # @return [Semverve::ResolvedConfiguration]
    attr_reader :configuration

    ##
    # Format handler used to parse and replace version content.
    #
    # @return [Semverve::Formats::ModuleConstants, Semverve::Formats::SimpleString]
    attr_reader :format

    ##
    # Absolute path to the configured version file.
    #
    # @return [String]
    def path
      configuration.absolute_version_file
    end

    ##
    # Reads the configured version file.
    #
    # @return [String]
    def read
      unless File.file?(path)
        raise Error, "Could not find version file #{path}. Run rake semverve:generate or set config.version_file."
      end

      File.read(path)
    end
  end
end
