# frozen_string_literal: true

require_relative "error"
require_relative "package_metadata"
require_relative "rails_config_metadata"
require_relative "version_code_references"
require_relative "version_references"

module Semverve
  ##
  # Registry and check adapters for version-maintenance surfaces.
  module VersionChecks
    class << self
      ##
      # Registers a core version check.
      #
      # @param [#name] check
      #
      # @return [#name]
      def register(check)
        core_checks[check.name] = check
      end

      ##
      # All checks available to task dispatch and validation.
      #
      # @param [Array<#name>] extra_checks
      #
      # @return [Array<#name>]
      def all(extra_checks: [])
        (core_checks.values + extra_checks).each_with_object({}) do |check, checks|
          checks[check.name] = check
        end.values
      end

      ##
      # Fetches a registered check by name.
      #
      # @param [Symbol, String] name
      # @param [Array<#name>] extra_checks
      #
      # @return [#name]
      def fetch(name, extra_checks: [])
        normalized_name = normalize_name(name)
        check = all(extra_checks: extra_checks).find { |candidate| candidate.name == normalized_name }
        return check if check

        raise Error, unknown_check_message([normalized_name], extra_checks: extra_checks)
      end

      ##
      # Validates and normalizes configured check names.
      #
      # @param [Array<Symbol, String>] checks
      # @param [Array<#name>] extra_checks
      #
      # @return [Array<Symbol>]
      def normalize(checks, extra_checks: [])
        normalized_checks = Array(checks).map { |check| normalize_name(check) }
        valid_names = names(extra_checks: extra_checks)
        return normalized_checks if normalized_checks.all? { |check| valid_names.include?(check) }

        invalid_checks = normalized_checks.reject { |check| valid_names.include?(check) }
        raise Error, unknown_check_message(invalid_checks, extra_checks: extra_checks)
      end

      ##
      # Registered check names.
      #
      # @param [Array<#name>] extra_checks
      #
      # @return [Array<Symbol>]
      def names(extra_checks: [])
        all(extra_checks: extra_checks).map(&:name)
      end

      ##
      # Default core version-maintenance surfaces for package projects.
      #
      # @return [Array<Symbol>]
      def default_names
        [:doc_references, :code_references, :package_metadata]
      end

      private

      ##
      # Core check registry.
      #
      # @return [Hash<Symbol, #name>]
      def core_checks
        @core_checks ||= {}
      end

      ##
      # Normalizes a check name.
      #
      # @param [Object] name
      #
      # @return [Symbol, Object]
      def normalize_name(name)
        name.respond_to?(:to_sym) ? name.to_sym : name
      end

      ##
      # Error message for invalid checks.
      #
      # @param [Array<Symbol>] invalid_checks
      # @param [Array<#name>] extra_checks
      #
      # @return [String]
      def unknown_check_message(invalid_checks, extra_checks:)
        valid_check_names = names(extra_checks: extra_checks).map(&:inspect)
        valid_checks = "#{valid_check_names[0...-1].join(", ")}, or #{valid_check_names.last}"
        "Unknown version check #{invalid_checks.map(&:inspect).join(", ")}. Use #{valid_checks}."
      end
    end

    ##
    # Base behavior for check adapters. Public check objects must expose name,
    # task_name, descriptions, labels, findings, and fix.
    class Check
      ##
      # Whether focused task accepts an exact target version argument.
      #
      # @return [Boolean]
      def targetable?
        false
      end

      ##
      # Whether findings should print a note when an exact target is already current.
      #
      # @return [Boolean]
      def exact_target_fix_noop_notice?
        false
      end

      ##
      # Rake task argument names for the focused task.
      #
      # @return [Array<Symbol>]
      def task_arguments
        targetable? ? [:version] : []
      end

      ##
      # Label used when reporting replacement counts.
      #
      # @return [String]
      def fix_label
        finding_label
      end

      ##
      # Finds mismatches.
      #
      # @return [Array]
      def findings(_configuration, _current_version, include_ignored: false, target_version: nil)
        raise NotImplementedError
      end

      ##
      # Fixes mismatches.
      #
      # @return [#changed_files, #replacement_count]
      def fix(_configuration, _current_version, target_version: nil)
        raise NotImplementedError
      end
    end

    ##
    # Documentation/reference version check.
    class DocReferences < Check
      ##
      # Initializes the check.
      #
      # @param [Class] scanner
      #
      # @return [Semverve::VersionChecks::DocReferences]
      def initialize(scanner: VersionReferences)
        @scanner = scanner
      end

      ##
      # Public check name used in +config.version_checks+.
      #
      # @return [Symbol]
      def name
        :doc_references
      end

      ##
      # Focused Rake task suffix.
      #
      # @return [Symbol]
      def task_name
        :references
      end

      ##
      # Focused check task description.
      #
      # @return [String]
      def check_description
        "Check configured files for stale version references"
      end

      ##
      # Focused fix task description.
      #
      # @return [String]
      def fix_description
        "Replace stale version references in configured files"
      end

      ##
      # Label printed for findings and replacement counts.
      #
      # @return [String]
      def finding_label
        "version reference"
      end

      ##
      # Message printed when no findings or replacements exist.
      #
      # @return [String]
      def clean_message
        "Version references are current."
      end

      def targetable?
        true
      end

      def exact_target_fix_noop_notice?
        true
      end

      def findings(configuration, current_version, include_ignored: false, target_version: nil)
        scanner.new(
          configuration,
          current_version,
          include_ignored: include_ignored,
          target_version: target_version
        ).findings
      end

      def fix(configuration, current_version, target_version: nil)
        scanner.new(configuration, current_version, target_version: target_version).fix
      end

      private

      ##
      # Scanner/fixer class used by the check.
      #
      # @return [Class]
      attr_reader :scanner
    end

    ##
    # Code literal version check.
    class CodeReferences < Check
      ##
      # Initializes the check.
      #
      # @param [Class] scanner
      #
      # @return [Semverve::VersionChecks::CodeReferences]
      def initialize(scanner: VersionCodeReferences)
        @scanner = scanner
      end

      ##
      # Public check name used in +config.version_checks+.
      #
      # @return [Symbol]
      def name
        :code_references
      end

      ##
      # Focused Rake task suffix.
      #
      # @return [Symbol]
      def task_name
        :code
      end

      ##
      # Focused check task description.
      #
      # @return [String]
      def check_description
        "Check configured code files for version literals"
      end

      ##
      # Focused fix task description.
      #
      # @return [String]
      def fix_description
        "Replace safe code version literals in configured files"
      end

      ##
      # Label printed for findings and replacement counts.
      #
      # @return [String]
      def finding_label
        "code version literal"
      end

      ##
      # Message printed when no findings or replacements exist.
      #
      # @return [String]
      def clean_message
        "Code version literals are current."
      end

      def targetable?
        true
      end

      def exact_target_fix_noop_notice?
        true
      end

      def findings(configuration, current_version, include_ignored: false, target_version: nil)
        scanner.new(
          configuration,
          current_version,
          include_ignored: include_ignored,
          target_version: target_version
        ).findings
      end

      def fix(configuration, current_version, target_version: nil)
        scanner.new(configuration, current_version, target_version: target_version).fix
      end

      private

      ##
      # Scanner/fixer class used by the check.
      #
      # @return [Class]
      attr_reader :scanner
    end

    ##
    # Package metadata version check.
    class PackageMetadataCheck < Check
      ##
      # Initializes the check.
      #
      # @param [Class] scanner
      #
      # @return [Semverve::VersionChecks::PackageMetadataCheck]
      def initialize(scanner: PackageMetadata)
        @scanner = scanner
      end

      ##
      # Public check name used in +config.version_checks+.
      #
      # @return [Symbol]
      def name
        :package_metadata
      end

      ##
      # Focused Rake task suffix.
      #
      # @return [Symbol]
      def task_name
        :package_metadata
      end

      ##
      # Focused check task description.
      #
      # @return [String]
      def check_description
        "Check package metadata for version mismatches"
      end

      ##
      # Focused fix task description.
      #
      # @return [String]
      def fix_description
        "Fix safe package metadata version mismatches"
      end

      ##
      # Package findings provide their own labels.
      #
      # @return [nil]
      def finding_label
        nil
      end

      def fix_label
        "package metadata version"
      end

      ##
      # Message printed when no findings or replacements exist.
      #
      # @return [String]
      def clean_message
        "Package metadata is current."
      end

      def findings(configuration, current_version, include_ignored: false, target_version: nil)
        scanner.new(configuration, current_version).findings
      end

      def fix(configuration, current_version, target_version: nil)
        scanner.new(configuration, current_version).fix
      end

      private

      ##
      # Scanner/fixer class used by the check.
      #
      # @return [Class]
      attr_reader :scanner
    end

    ##
    # Rails config metadata version check.
    class RailsConfigMetadataCheck < Check
      ##
      # Initializes the check.
      #
      # @param [Class] scanner
      #
      # @return [Semverve::VersionChecks::RailsConfigMetadataCheck]
      def initialize(scanner: RailsConfigMetadata)
        @scanner = scanner
      end

      ##
      # Public check name used in +config.version_checks+.
      #
      # @return [Symbol]
      def name
        :rails_config_metadata
      end

      ##
      # Focused Rake task suffix.
      #
      # @return [Symbol]
      def task_name
        :rails_config_metadata
      end

      ##
      # Focused check task description.
      #
      # @return [String]
      def check_description
        "Check Rails config metadata for version mismatches"
      end

      ##
      # Focused fix task description.
      #
      # @return [String]
      def fix_description
        "Fix safe Rails config metadata version mismatches"
      end

      ##
      # Label printed for Rails config metadata findings and replacements.
      #
      # @return [String]
      def finding_label
        "Rails config version"
      end

      ##
      # Message printed when no findings or replacements exist.
      #
      # @return [String]
      def clean_message
        "Rails config metadata is current."
      end

      def findings(configuration, current_version, include_ignored: false, target_version: nil)
        scanner.new(configuration, current_version).findings
      end

      def fix(configuration, current_version, target_version: nil)
        scanner.new(configuration, current_version).fix
      end

      private

      ##
      # Scanner/fixer class used by the check.
      #
      # @return [Class]
      attr_reader :scanner
    end
  end
end

Semverve::VersionChecks.register(Semverve::VersionChecks::DocReferences.new)
Semverve::VersionChecks.register(Semverve::VersionChecks::CodeReferences.new)
Semverve::VersionChecks.register(Semverve::VersionChecks::PackageMetadataCheck.new)
