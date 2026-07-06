# frozen_string_literal: true

require_relative "project_metadata"

module Semverve
  ##
  # Mutable configuration used before Semverve resolves project defaults.
  class Configuration
    ##
    # Whether increments should run +bundle lock+ after writing a version.
    #
    # @return [Boolean]
    attr_accessor :bundle_lock

    ##
    # Callable used to run shell commands such as +bundle lock+.
    #
    # @return [#call]
    attr_accessor :command_runner

    ##
    # Version-file format to read, replace, or generate.
    #
    # @return [Symbol, String]
    attr_accessor :format

    ##
    # Explicit gem name to use instead of inferring one from the project.
    #
    # @return [String, nil]
    attr_accessor :gem_name

    ##
    # Explicit Ruby module name to use in generated version files.
    #
    # @return [String, nil]
    attr_accessor :module_name

    ##
    # Project root used when inferring metadata and expanding paths.
    #
    # @return [String, nil]
    attr_accessor :root

    ##
    # Explicit version-file path relative to the project root.
    #
    # @return [String, nil]
    attr_accessor :version_file

    ##
    # Initializes configuration with Semverve's default settings.
    #
    # @return [Semverve::Configuration]
    def initialize
      @bundle_lock = false
      @command_runner = ->(command) { system(command) }
      @format = :module
    end

    ##
    # Resolves explicit configuration and inferred project metadata.
    #
    # @return [Semverve::ResolvedConfiguration]
    def resolved
      metadata = ProjectMetadata.new(self)

      ResolvedConfiguration.new(
        bundle_lock: bundle_lock,
        command_runner: command_runner,
        format: normalized_format,
        gem_name: metadata.gem_name,
        module_name: metadata.module_name,
        root: expanded_root,
        version_file: metadata.version_file
      )
    end

    ##
    # Absolute project root.
    #
    # @return [String]
    def expanded_root
      File.expand_path(root || Dir.pwd)
    end

    ##
    # Configured format normalized for lookup.
    #
    # @return [Symbol]
    def normalized_format
      format.to_sym
    end
  end

  ##
  # Immutable configuration with all project defaults resolved.
  class ResolvedConfiguration
    ##
    # Whether increments should run +bundle lock+ after writing a version.
    #
    # @return [Boolean]
    attr_reader :bundle_lock

    ##
    # Callable used to run shell commands such as +bundle lock+.
    #
    # @return [#call]
    attr_reader :command_runner

    ##
    # Resolved version-file format.
    #
    # @return [Symbol]
    attr_reader :format

    ##
    # Resolved gem name.
    #
    # @return [String]
    attr_reader :gem_name

    ##
    # Resolved Ruby module name.
    #
    # @return [String]
    attr_reader :module_name

    ##
    # Absolute project root.
    #
    # @return [String]
    attr_reader :root

    ##
    # Resolved version-file path relative to the project root.
    #
    # @return [String]
    attr_reader :version_file

    ##
    # Initializes a resolved configuration.
    #
    # @param [Boolean] bundle_lock
    # @param [#call] command_runner
    # @param [Symbol] format
    # @param [String] gem_name
    # @param [String] module_name
    # @param [String] root
    # @param [String] version_file
    #
    # @return [Semverve::ResolvedConfiguration]
    def initialize(bundle_lock:, command_runner:, format:, gem_name:, module_name:, root:, version_file:)
      @bundle_lock = bundle_lock
      @command_runner = command_runner
      @format = format
      @gem_name = gem_name
      @module_name = module_name
      @root = root
      @version_file = version_file
    end

    ##
    # Absolute path to the resolved version file.
    #
    # @return [String]
    def absolute_version_file
      File.expand_path(version_file, root)
    end
  end
end
