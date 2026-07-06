# frozen_string_literal: true

require "rake"

require_relative "error"
require_relative "project_metadata"

module Semverve
  ##
  # Mutable configuration used before Semverve resolves project defaults.
  class Configuration
    VALID_VERSION_CHECKS = [:doc_references, :code_references, :metadata].freeze
    DEFAULT_VERSION_CODE_REFERENCE_PATTERN = /^\s*(?:(?:[A-Z]\w*::)*(?:[A-Z]\w*VERSION[A-Z0-9_]*|VERSION)|(?:[a-z_]\w*|self)\.version)\s*=\s*(?<quote>["'])(?<version>\d+\.\d+\.\d+)\k<quote>/

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
    # Code files to scan for safe version literals.
    #
    # @return [Rake::FileList]
    attr_accessor :version_code_reference_files

    ##
    # Pattern used to find safe version literals in code files.
    #
    # @return [Regexp]
    attr_reader :version_code_reference_pattern

    ##
    # Documentation files to scan for version references.
    #
    # @return [Rake::FileList]
    attr_accessor :version_doc_reference_files

    ##
    # Version-maintenance surfaces run by the umbrella check and fix tasks.
    #
    # @return [Array<Symbol, String>]
    attr_reader :version_checks

    ##
    # Version-reference comparison mode.
    #
    # @return [Symbol, String]
    attr_accessor :version_reference_mode

    ##
    # Initializes configuration with Semverve's default settings.
    #
    # @return [Semverve::Configuration]
    def initialize
      @bundle_lock = false
      @command_runner = ->(command) { system(command) }
      @format = :module
      @version_code_reference_files = Rake::FileList[]
      self.version_code_reference_pattern = DEFAULT_VERSION_CODE_REFERENCE_PATTERN
      @version_doc_reference_files = Rake::FileList["README*", "**/README*"].exclude(
        ".git/**/*",
        "coverage/**/*",
        "tmp/**/*",
        "vendor/**/*"
      )
      @version_reference_mode = :older
      self.version_checks = VALID_VERSION_CHECKS
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
        version_file: metadata.version_file,
        version_checks: normalized_version_checks,
        version_code_reference_files: version_code_reference_files,
        version_code_reference_pattern: version_code_reference_pattern,
        version_doc_reference_files: version_doc_reference_files,
        version_reference_mode: normalized_version_reference_mode
      )
    end

    ##
    # Sets the pattern used to find safe version literals in code files.
    #
    # @param [Regexp] pattern
    #
    # @return [Regexp]
    def version_code_reference_pattern=(pattern)
      validate_version_code_reference_pattern(pattern)
      @version_code_reference_pattern = pattern
    end

    ##
    # Sets the version-maintenance surfaces run by umbrella tasks.
    #
    # @param [Array<Symbol, String>] checks
    #
    # @return [Array<Symbol>]
    def version_checks=(checks)
      @version_checks = normalize_version_checks(checks)
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

    ##
    # Configured version checks normalized for lookup.
    #
    # @return [Array<Symbol>]
    def normalized_version_checks
      normalize_version_checks(version_checks)
    end

    ##
    # Configured version-reference mode normalized for lookup.
    #
    # @return [Symbol]
    def normalized_version_reference_mode
      version_reference_mode.to_sym
    end

    ##
    # Normalizes and validates umbrella version checks.
    #
    # @param [Array<Symbol, String>] checks
    #
    # @return [Array<Symbol>]
    def normalize_version_checks(checks)
      normalized_checks = Array(checks).map do |check|
        check.respond_to?(:to_sym) ? check.to_sym : check
      end
      return normalized_checks if normalized_checks.all? { |check| VALID_VERSION_CHECKS.include?(check) }

      invalid_checks = normalized_checks.reject { |check| VALID_VERSION_CHECKS.include?(check) }
      valid_check_names = VALID_VERSION_CHECKS.map(&:inspect)
      valid_checks = "#{valid_check_names[0...-1].join(", ")}, or #{valid_check_names.last}"
      raise Error, "Unknown version check #{invalid_checks.map(&:inspect).join(", ")}. Use #{valid_checks}."
    end

    ##
    # Validates the configured code reference pattern.
    #
    # @param [Object] pattern
    #
    # @return [void]
    def validate_version_code_reference_pattern(pattern)
      unless pattern.is_a?(Regexp)
        raise Error, "version_code_reference_pattern must be a Regexp."
      end

      unless pattern.named_captures.key?("version")
        raise Error, "version_code_reference_pattern must include a named capture called version."
      end
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
    # Resolved version-maintenance surfaces run by umbrella tasks.
    #
    # @return [Array<Symbol>]
    attr_reader :version_checks

    ##
    # Resolved code files to scan for safe version literals.
    #
    # @return [Rake::FileList]
    attr_reader :version_code_reference_files

    ##
    # Resolved code pattern used to scan safe version literals.
    #
    # @return [Regexp]
    attr_reader :version_code_reference_pattern

    ##
    # Resolved documentation files to scan for version references.
    #
    # @return [Rake::FileList]
    attr_reader :version_doc_reference_files

    ##
    # Resolved version-reference comparison mode.
    #
    # @return [Symbol]
    attr_reader :version_reference_mode

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
    # @param [Array<Symbol>] version_checks
    # @param [Rake::FileList] version_code_reference_files
    # @param [Regexp] version_code_reference_pattern
    # @param [Rake::FileList] version_doc_reference_files
    # @param [Symbol] version_reference_mode
    #
    # @return [Semverve::ResolvedConfiguration]
    def initialize(
      bundle_lock:,
      command_runner:,
      format:,
      gem_name:,
      module_name:,
      root:,
      version_file:,
      version_checks:,
      version_code_reference_files:,
      version_code_reference_pattern:,
      version_doc_reference_files:,
      version_reference_mode:
    )
      @bundle_lock = bundle_lock
      @command_runner = command_runner
      @format = format
      @gem_name = gem_name
      @module_name = module_name
      @root = root
      @version_file = version_file
      @version_checks = version_checks
      @version_code_reference_files = version_code_reference_files
      @version_code_reference_pattern = version_code_reference_pattern
      @version_doc_reference_files = version_doc_reference_files
      @version_reference_mode = version_reference_mode
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
