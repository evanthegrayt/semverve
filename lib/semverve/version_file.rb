# frozen_string_literal: true

require_relative "error"
require_relative "formats"

module Semverve
  ##
  # Reads and updates an existing version file.
  class VersionFile
    ##
    # Result of attempting to update a version file.
    class UpdateResult
      ##
      # Version parsed before the update.
      #
      # @return [Semverve::SemanticVersion]
      attr_reader :previous_version

      ##
      # Version requested by the update.
      #
      # @return [Semverve::SemanticVersion]
      attr_reader :version

      ##
      # Initializes an update result.
      #
      # @param [Semverve::SemanticVersion] previous_version
      # @param [Semverve::SemanticVersion] version
      # @param [Boolean] changed
      #
      # @return [Semverve::VersionFile::UpdateResult]
      def initialize(previous_version:, version:, changed:)
        @previous_version = previous_version
        @version = version
        @changed = changed
      end

      ##
      # Whether the version file was changed.
      #
      # @return [Boolean]
      def changed?
        @changed
      end
    end

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
    # @return [Semverve::VersionFile::UpdateResult]
    def increment(level)
      update { |version| version.increment(level) }
    end

    ##
    # Sets the version file to an explicit semantic version.
    #
    # @param [Semverve::SemanticVersion] version
    #
    # @return [Semverve::VersionFile::UpdateResult]
    def set(version)
      update { version }
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

    ##
    # Updates the version file with the version returned by the block.
    #
    # @yieldparam [Semverve::SemanticVersion] version
    #
    # @return [Semverve::VersionFile::UpdateResult]
    def update
      content = read
      previous_version = format.parse(content, path: path)
      next_version = yield previous_version
      changed = previous_version != next_version

      File.write(path, format.replace(content, next_version, path: path)) if changed

      UpdateResult.new(
        previous_version: previous_version,
        version: next_version,
        changed: changed
      )
    end
  end
end
