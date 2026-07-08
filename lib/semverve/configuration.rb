# frozen_string_literal: true

require "rake"

require_relative "adapters"
require_relative "error"
require_relative "project_metadata"
require_relative "version_checks"

module Semverve
  ##
  # Mutable configuration used before Semverve resolves project defaults.
  class Configuration
    ##
    # Version-maintenance surfaces supported by umbrella check and fix tasks.
    #
    # @return [Array<Symbol>]
    VALID_VERSION_CHECKS = VersionChecks.names(extra_checks: Adapters.checks).freeze

    ##
    # Default version-maintenance surfaces for package projects.
    #
    # @return [Array<Symbol>]
    DEFAULT_VERSION_CHECKS = VersionChecks.default_names.freeze

    ##
    # Release-readiness surfaces supported by release check tasks.
    #
    # @return [Array<Symbol>]
    VALID_RELEASE_CHECKS = [:rubygems].freeze

    ##
    # Default Ruby pattern for code version literals that are safe to rewrite.
    #
    # @return [Regexp]
    DEFAULT_VERSION_CODE_REFERENCE_PATTERN = VersionCodeReferences::RUBY_ASSIGNMENT_PATTERN

    ##
    # Framework adapter used to apply project defaults.
    #
    # @return [Symbol, String, nil]
    attr_reader :adapter

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
    attr_reader :format

    ##
    # Explicit gem name to use instead of inferring one from the project.
    #
    # @return [String, nil]
    attr_reader :gem_name

    ##
    # Explicit Ruby module name to use in generated version files.
    #
    # @return [String, nil]
    attr_reader :module_name

    ##
    # Framework preset used to apply project defaults.
    #
    # @return [Symbol, String, nil]
    def preset
      adapter
    end

    ##
    # Release-readiness surfaces run by the release check task.
    #
    # @return [Array<Symbol, String>]
    attr_reader :release_checks

    ##
    # Project root used when inferring metadata and expanding paths.
    #
    # @return [String, nil]
    attr_reader :root

    ##
    # RubyGems-compatible host used for published-version checks.
    #
    # @return [String]
    attr_accessor :rubygems_host

    ##
    # Explicit version-file path relative to the project root.
    #
    # @return [String, nil]
    attr_reader :version_file

    ##
    # Rake namespace used when installing Semverve tasks.
    #
    # @return [String, Symbol]
    attr_accessor :task_namespace

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
    # Project-relative file/line/version references to ignore.
    #
    # @return [Hash]
    attr_accessor :version_reference_ignores

    ##
    # Version-maintenance surfaces run by the umbrella check and fix tasks.
    #
    # @return [Array<Symbol, String>]
    attr_reader :version_checks

    ##
    # Version matching mode for reference and code-literal checks.
    #
    # @return [Symbol, String]
    attr_accessor :version_match_mode

    ##
    # Initializes configuration with Semverve's default settings.
    #
    # @return [Semverve::Configuration]
    def initialize
      @explicit_attributes = []
      @bundle_lock = false
      @command_runner = ->(command) { system(command) }
      @format = :module
      @adapter = nil
      @rubygems_host = "https://rubygems.org"
      @task_namespace = :semverve
      @version_code_reference_files = Rake::FileList[]
      self.version_code_reference_pattern = DEFAULT_VERSION_CODE_REFERENCE_PATTERN
      @version_doc_reference_files = Rake::FileList["README*", "**/README*"].exclude(
        ".git/**/*",
        "coverage/**/*",
        "tmp/**/*",
        "vendor/**/*"
      )
      @version_reference_ignores = {}
      @version_match_mode = :older
      self.release_checks = []
      @version_checks = DEFAULT_VERSION_CHECKS
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
        release_checks: normalized_release_checks,
        root: expanded_root,
        rubygems_host: rubygems_host,
        task_namespace: normalized_task_namespace,
        version_file: metadata.version_file,
        version_checks: normalized_version_checks,
        version_code_reference_files: version_code_reference_files,
        version_code_reference_pattern: version_code_reference_pattern,
        version_doc_reference_files: version_doc_reference_files,
        version_reference_ignores: version_reference_ignores,
        version_match_mode: normalized_version_match_mode
      )
    end

    ##
    # Sets the version-file format.
    #
    # @param [Symbol, String] format
    #
    # @return [Symbol, String]
    def format=(format)
      set_explicit(:format, format)
    end

    ##
    # Sets the gem name used for package metadata checks.
    #
    # @param [String, nil] gem_name
    #
    # @return [String, nil]
    def gem_name=(gem_name)
      set_explicit(:gem_name, gem_name)
    end

    ##
    # Sets the module name used for generated version files.
    #
    # @param [String, nil] module_name
    #
    # @return [String, nil]
    def module_name=(module_name)
      set_explicit(:module_name, module_name)
    end

    ##
    # Sets the framework adapter used for project defaults.
    #
    # @param [Symbol, String, nil] adapter
    #
    # @return [Symbol, nil]
    def adapter=(adapter)
      @adapter_defaults = nil
      @adapter = adapter.nil? ? nil : Adapters.fetch(adapter).name
    end

    ##
    # Sets the framework preset used for project defaults.
    #
    # @param [Symbol, String, nil] preset
    #
    # @return [Symbol, nil]
    def preset=(preset)
      self.adapter = preset
    end

    ##
    # Sets the release-readiness surfaces run by the release check task.
    #
    # @param [Array<Symbol, String>] checks
    #
    # @return [Array<Symbol>]
    def release_checks=(checks)
      @release_checks = normalize_release_checks(checks)
    end

    ##
    # Sets the project root used when expanding paths.
    #
    # @param [String, nil] root
    #
    # @return [String, nil]
    def root=(root)
      set_explicit(:root, root)
    end

    ##
    # Sets the version-file path relative to the project root.
    #
    # @param [String, nil] version_file
    #
    # @return [String, nil]
    def version_file=(version_file)
      set_explicit(:version_file, version_file)
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
      set_explicit(:version_checks, normalize_version_checks(checks))
    end

    ##
    # Absolute project root.
    #
    # @return [String]
    def expanded_root
      File.expand_path(resolved_value(:root) || Dir.pwd)
    end

    ##
    # Configured format normalized for lookup.
    #
    # @return [Symbol]
    def normalized_format
      resolved_value(:format).to_sym
    end

    ##
    # Configured release checks normalized for lookup.
    #
    # @return [Array<Symbol>]
    def normalized_release_checks
      normalize_release_checks(release_checks)
    end

    ##
    # Resolved value for a configurable attribute before metadata inference.
    #
    # @param [Symbol] attribute
    #
    # @return [Object]
    def resolved_value(attribute)
      return public_send(attribute) if explicit_attribute?(attribute)
      return adapter_defaults[attribute] if adapter_defaults.key?(attribute)

      public_send(attribute)
    end

    ##
    # Whether package names should be inferred from project files.
    #
    # @return [Boolean]
    def infer_package_name?
      Adapters.infer_package_name?(adapter)
    end

    ##
    # Configured version checks normalized for lookup.
    #
    # @return [Array<Symbol>]
    def normalized_version_checks
      normalize_version_checks(resolved_value(:version_checks))
    end

    ##
    # Configured version matching mode normalized for lookup.
    #
    # @return [Symbol]
    def normalized_version_match_mode
      version_match_mode.to_sym
    end

    ##
    # Configured Rake task namespace normalized for task-name interpolation.
    #
    # @return [String]
    def normalized_task_namespace
      namespace = task_namespace.to_s
      raise Error, "task_namespace must not be empty." if namespace.empty?

      namespace
    end

    ##
    # Normalizes and validates umbrella version checks.
    #
    # @param [Array<Symbol, String>] checks
    #
    # @return [Array<Symbol>]
    def normalize_version_checks(checks)
      VersionChecks.normalize(checks, extra_checks: Adapters.checks)
    end

    ##
    # Normalizes and validates release checks.
    #
    # @param [Array<Symbol, String>] checks
    #
    # @return [Array<Symbol>]
    def normalize_release_checks(checks)
      normalized_checks = Array(checks).map do |check|
        check.respond_to?(:to_sym) ? check.to_sym : check
      end
      return normalized_checks if normalized_checks.all? { |check| VALID_RELEASE_CHECKS.include?(check) }

      invalid_checks = normalized_checks.reject { |check| VALID_RELEASE_CHECKS.include?(check) }
      raise Error, "Unknown release check #{invalid_checks.map(&:inspect).join(", ")}. Use :rubygems."
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

    private

    ##
    # Whether an attribute was explicitly set by the user.
    #
    # @param [Symbol] attribute
    #
    # @return [Boolean]
    def explicit_attribute?(attribute)
      @explicit_attributes.include?(attribute)
    end

    ##
    # Stores an explicit user-provided setting.
    #
    # @param [Symbol] attribute
    # @param [Object] value
    #
    # @return [Object]
    def set_explicit(attribute, value)
      @adapter_defaults = nil
      @explicit_attributes << attribute unless explicit_attribute?(attribute)
      instance_variable_set(:"@#{attribute}", value)
    end

    ##
    # Defaults supplied by the configured adapter.
    #
    # @return [Hash]
    def adapter_defaults
      @adapter_defaults ||= Adapters.defaults_for(adapter, self)
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
    # @return [String, nil]
    attr_reader :gem_name

    ##
    # Resolved Ruby module name.
    #
    # @return [String]
    attr_reader :module_name

    ##
    # Resolved release-readiness surfaces run by the release check task.
    #
    # @return [Array<Symbol>]
    attr_reader :release_checks

    ##
    # Absolute project root.
    #
    # @return [String]
    attr_reader :root

    ##
    # Resolved RubyGems-compatible host used for published-version checks.
    #
    # @return [String]
    attr_reader :rubygems_host

    ##
    # Resolved Rake task namespace.
    #
    # @return [String]
    attr_reader :task_namespace

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
    # Resolved project-relative file/line/version references to ignore.
    #
    # @return [Hash]
    attr_reader :version_reference_ignores

    ##
    # Resolved version matching mode for reference and code-literal checks.
    #
    # @return [Symbol]
    attr_reader :version_match_mode

    ##
    # Initializes a resolved configuration.
    #
    # @param [Boolean] bundle_lock
    # @param [#call] command_runner
    # @param [Symbol] format
    # @param [String, nil] gem_name
    # @param [String] module_name
    # @param [Array<Symbol>] release_checks
    # @param [String] root
    # @param [String] rubygems_host
    # @param [String] task_namespace
    # @param [String] version_file
    # @param [Array<Symbol>] version_checks
    # @param [Rake::FileList] version_code_reference_files
    # @param [Regexp] version_code_reference_pattern
    # @param [Rake::FileList] version_doc_reference_files
    # @param [Hash] version_reference_ignores
    # @param [Symbol] version_match_mode
    #
    # @return [Semverve::ResolvedConfiguration]
    def initialize(
      bundle_lock:,
      command_runner:,
      format:,
      gem_name:,
      module_name:,
      release_checks:,
      root:,
      rubygems_host:,
      task_namespace:,
      version_file:,
      version_checks:,
      version_code_reference_files:,
      version_code_reference_pattern:,
      version_doc_reference_files:,
      version_reference_ignores:,
      version_match_mode:
    )
      @bundle_lock = bundle_lock
      @command_runner = command_runner
      @format = format
      @gem_name = gem_name
      @module_name = module_name
      @release_checks = release_checks
      @root = root
      @rubygems_host = rubygems_host
      @task_namespace = task_namespace
      @version_file = version_file
      @version_checks = version_checks
      @version_code_reference_files = version_code_reference_files
      @version_code_reference_pattern = version_code_reference_pattern
      @version_doc_reference_files = version_doc_reference_files
      @version_reference_ignores = version_reference_ignores
      @version_match_mode = version_match_mode
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
