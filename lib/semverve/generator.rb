# frozen_string_literal: true

require "fileutils"

require_relative "error"
require_relative "formats"
require_relative "semantic_version"

module Semverve
  ##
  # Generates new Ruby version files from Semverve configuration.
  class Generator
    ##
    # Default version used when a version argument is not provided.
    #
    # @return [String]
    DEFAULT_VERSION = "0.1.0" # semverve:ignore-version-reference

    ##
    # Initializes a version-file generator.
    #
    # @param [Semverve::ResolvedConfiguration] configuration
    # @param [String, nil] version
    # @param [String, Symbol, nil] format
    # @param [Boolean] force
    #
    # @return [Semverve::Generator]
    def initialize(configuration, version: nil, format: nil, force: false)
      @configuration = configuration
      @version = version
      @format = format
      @force = force
    end

    ##
    # Generates the configured version file.
    #
    # @return [String]
    def generate
      version = SemanticVersion.parse(requested_version)
      format = Formats.fetch(requested_format)
      path = configuration.absolute_version_file

      if File.exist?(path) && !force?
        raise Error, "Version file already exists at #{path}. Run rake '#{configuration.task_namespace}:generate[force]' to overwrite it."
      end

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, format.generate(version, module_name: configuration.module_name))

      path
    end

    private

    ##
    # Resolved configuration used for generation.
    #
    # @return [Semverve::ResolvedConfiguration]
    attr_reader :configuration, :version, :format, :force

    ##
    # Requested version or default.
    #
    # @return [String]
    def requested_version
      version || DEFAULT_VERSION
    end

    ##
    # Requested format or configured default.
    #
    # @return [String, Symbol]
    def requested_format
      format || configuration.format
    end

    ##
    # Whether generation should overwrite an existing version file.
    #
    # @return [Boolean]
    def force?
      force
    end
  end
end
