# frozen_string_literal: true

require_relative "adapters"
require_relative "version_file"
require_relative "version_checks"

module Semverve
  ##
  # Runs Semverve version-maintenance checks without tying them to Rake output.
  class VersionAudit
    ##
    # A finding with the check metadata needed by callers and reporters.
    class LabeledFinding
      ##
      # Check that produced the finding.
      #
      # @return [#name]
      attr_reader :check

      ##
      # User-facing finding label.
      #
      # @return [String]
      attr_reader :label

      ##
      # Underlying finding data.
      #
      # @return [Semverve::Finding]
      attr_reader :finding

      ##
      # Initializes a labeled finding.
      #
      # @param [#name] check
      # @param [String] label
      # @param [Semverve::Finding] finding
      #
      # @return [Semverve::VersionAudit::LabeledFinding]
      def initialize(check:, label:, finding:)
        @check = check
        @label = label
        @finding = finding
      end
    end

    ##
    # Findings for a single check.
    class FindingGroup
      ##
      # Check that produced the findings.
      #
      # @return [#name]
      attr_reader :check

      ##
      # Default label for findings in this group.
      #
      # @return [String, nil]
      attr_reader :label

      ##
      # Raw finding objects returned by the check.
      #
      # @return [Array<Semverve::Finding>]
      attr_reader :findings

      ##
      # Initializes a finding group.
      #
      # @param [#name] check
      # @param [String, nil] label
      # @param [Array<Semverve::Finding>] findings
      #
      # @return [Semverve::VersionAudit::FindingGroup]
      def initialize(check:, label:, findings:)
        @check = check
        @label = label
        @findings = findings
      end

      ##
      # Findings decorated with labels and check metadata.
      #
      # @return [Array<Semverve::VersionAudit::LabeledFinding>]
      def labeled_findings
        findings.map do |finding|
          LabeledFinding.new(check: check, label: label || finding.label, finding: finding)
        end
      end
    end

    ##
    # Result of running one or more checks.
    class CheckResult
      ##
      # Version from the configured version file.
      #
      # @return [Semverve::SemanticVersion]
      attr_reader :current_version

      ##
      # Exact target version requested by the caller, if any.
      #
      # @return [Semverve::SemanticVersion, nil]
      attr_reader :target_version

      ##
      # Finding groups by check.
      #
      # @return [Array<Semverve::VersionAudit::FindingGroup>]
      attr_reader :groups

      ##
      # Message callers may display when the result is clean.
      #
      # @return [String]
      attr_reader :clean_message

      ##
      # Initializes a check result.
      #
      # @param [Semverve::SemanticVersion] current_version
      # @param [Semverve::SemanticVersion, nil] target_version
      # @param [Array<Semverve::VersionAudit::FindingGroup>] groups
      # @param [String] clean_message
      #
      # @return [Semverve::VersionAudit::CheckResult]
      def initialize(current_version:, target_version:, groups:, clean_message:)
        @current_version = current_version
        @target_version = target_version
        @groups = groups
        @clean_message = clean_message
      end

      ##
      # All findings with labels and check metadata.
      #
      # @return [Array<Semverve::VersionAudit::LabeledFinding>]
      def findings
        groups.flat_map(&:labeled_findings)
      end

      ##
      # Whether all checks passed.
      #
      # @return [Boolean]
      def clean?
        findings.empty?
      end

      ##
      # Whether findings should warn that exact-target fixes would be no-ops.
      #
      # @return [Boolean]
      def current_target_fix_noop_notice?
        target_version == current_version &&
          findings.any? { |finding| finding.check.exact_target_fix_noop_notice? }
      end
    end

    ##
    # Fix result for a single check.
    class FixResultGroup
      ##
      # Check that produced the fix result.
      #
      # @return [#name]
      attr_reader :check

      ##
      # Label used for replacement counts.
      #
      # @return [String]
      attr_reader :label

      ##
      # Raw fix result returned by the check.
      #
      # @return [Semverve::FixResult]
      attr_reader :result

      ##
      # Initializes a fix result group.
      #
      # @param [#name] check
      # @param [String] label
      # @param [Semverve::FixResult] result
      #
      # @return [Semverve::VersionAudit::FixResultGroup]
      def initialize(check:, label:, result:)
        @check = check
        @label = label
        @result = result
      end
    end

    ##
    # Result of running one or more fixes.
    class FixResult
      ##
      # Version from the configured version file.
      #
      # @return [Semverve::SemanticVersion]
      attr_reader :current_version

      ##
      # Exact target version requested by the caller, if any.
      #
      # @return [Semverve::SemanticVersion, nil]
      attr_reader :target_version

      ##
      # Fix result groups by check.
      #
      # @return [Array<Semverve::VersionAudit::FixResultGroup>]
      attr_reader :groups

      ##
      # Message callers may display when no fixes were needed.
      #
      # @return [String]
      attr_reader :clean_message

      ##
      # Initializes a fix result.
      #
      # @param [Semverve::SemanticVersion] current_version
      # @param [Semverve::SemanticVersion, nil] target_version
      # @param [Array<Semverve::VersionAudit::FixResultGroup>] groups
      # @param [String] clean_message
      # @param [Boolean] noop
      #
      # @return [Semverve::VersionAudit::FixResult]
      def initialize(current_version:, target_version:, groups:, clean_message:, noop: false)
        @current_version = current_version
        @target_version = target_version
        @groups = groups
        @clean_message = clean_message
        @noop = noop
      end

      ##
      # Total replacements made by all fixers.
      #
      # @return [Integer]
      def replacement_count
        groups.sum { |group| group.result.replacement_count }
      end

      ##
      # Whether any fixer ran bundle lock.
      #
      # @return [Boolean]
      def bundle_lock_ran?
        groups.any? { |group| group.result.bundle_lock_ran }
      end

      ##
      # Whether no file changes or bundle lock updates were needed.
      #
      # @return [Boolean]
      def clean?
        replacement_count.zero? && !bundle_lock_ran?
      end

      ##
      # Whether the caller requested an exact target that is already current.
      #
      # @return [Boolean]
      def noop?
        @noop
      end
    end

    ##
    # Resolved configuration used by the audit.
    #
    # @return [Semverve::ResolvedConfiguration]
    attr_reader :configuration

    ##
    # Available check objects.
    #
    # @return [Array<#name>]
    attr_reader :checks

    ##
    # Whether ignored findings should be included.
    #
    # @return [Boolean]
    attr_reader :include_ignored

    ##
    # Initializes a version audit.
    #
    # @param [Semverve::ResolvedConfiguration] configuration
    # @param [Array<#name>] checks
    # @param [Boolean] include_ignored
    #
    # @return [Semverve::VersionAudit]
    def initialize(
      configuration: Semverve.configuration.resolved,
      checks: VersionChecks.all(extra_checks: Adapters.checks),
      include_ignored: false
    )
      @configuration = configuration
      @checks = checks
      @include_ignored = include_ignored
    end

    ##
    # Current semantic version from the configured version file.
    #
    # @return [Semverve::SemanticVersion]
    def current_version
      @current_version ||= VersionFile.new(configuration).current
    end

    ##
    # Checks all configured version-maintenance surfaces.
    #
    # @param [Semverve::SemanticVersion, nil] target_version
    #
    # @return [Semverve::VersionAudit::CheckResult]
    def check(target_version: nil)
      CheckResult.new(
        current_version: current_version,
        target_version: target_version,
        groups: configured_checks.map { |check| finding_group(check, target_version) },
        clean_message: "Version checks passed."
      )
    end

    ##
    # Checks one version-maintenance surface.
    #
    # @param [Symbol, String] name
    # @param [Semverve::SemanticVersion, nil] target_version
    #
    # @return [Semverve::VersionAudit::CheckResult]
    def check_one(name, target_version: nil)
      check = fetch_check(name)

      CheckResult.new(
        current_version: current_version,
        target_version: target_version,
        groups: [finding_group(check, target_version)],
        clean_message: check.clean_message
      )
    end

    ##
    # Fixes all configured version-maintenance surfaces.
    #
    # @param [Semverve::SemanticVersion, nil] target_version
    #
    # @return [Semverve::VersionAudit::FixResult]
    def fix(target_version: nil)
      return noop_fix_result(target_version, "Version checks passed.") if target_version == current_version

      FixResult.new(
        current_version: current_version,
        target_version: target_version,
        groups: configured_checks.map { |check| fix_group(check, target_version) },
        clean_message: "Version checks passed."
      )
    end

    ##
    # Fixes one version-maintenance surface.
    #
    # @param [Symbol, String] name
    # @param [Semverve::SemanticVersion, nil] target_version
    #
    # @return [Semverve::VersionAudit::FixResult]
    def fix_one(name, target_version: nil)
      check = fetch_check(name)
      return noop_fix_result(target_version, check.clean_message) if target_version == current_version

      FixResult.new(
        current_version: current_version,
        target_version: target_version,
        groups: [fix_group(check, target_version)],
        clean_message: check.clean_message
      )
    end

    private

    ##
    # Configured checks enabled for umbrella checks and fixes.
    #
    # @return [Array<#name>]
    def configured_checks
      configuration.version_checks.map { |name| fetch_check(name) }
    end

    ##
    # Finds an available check by public name or task name.
    #
    # @param [Symbol, String] name
    #
    # @return [#name]
    def fetch_check(name)
      normalized_name = normalize_name(name)
      check = checks.find do |candidate|
        candidate.name == normalized_name || candidate.task_name == normalized_name
      end
      return check if check

      raise Error, unknown_check_message(normalized_name)
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
    # User-facing error for unknown check names.
    #
    # @param [Object] name
    #
    # @return [String]
    def unknown_check_message(name)
      valid_check_names = checks.map(&:name).map(&:inspect)
      valid_checks = "#{valid_check_names[0...-1].join(", ")}, or #{valid_check_names.last}"
      "Unknown version check #{name.inspect}. Use #{valid_checks}."
    end

    ##
    # Finding group for a check.
    #
    # @param [#findings] check
    # @param [Semverve::SemanticVersion, nil] target_version
    #
    # @return [Semverve::VersionAudit::FindingGroup]
    def finding_group(check, target_version)
      FindingGroup.new(
        check: check,
        label: check.finding_label,
        findings: check.findings(
          configuration,
          current_version,
          include_ignored: include_ignored,
          target_version: target_version_for(check, target_version)
        )
      )
    end

    ##
    # Fix result group for a check.
    #
    # @param [#fix] check
    # @param [Semverve::SemanticVersion, nil] target_version
    #
    # @return [Semverve::VersionAudit::FixResultGroup]
    def fix_group(check, target_version)
      FixResultGroup.new(
        check: check,
        label: check.fix_label,
        result: check.fix(
          configuration,
          current_version,
          target_version: target_version_for(check, target_version)
        )
      )
    end

    ##
    # Applies an exact target only to targetable checks.
    #
    # @param [#targetable?] check
    # @param [Semverve::SemanticVersion, nil] target_version
    #
    # @return [Semverve::SemanticVersion, nil]
    def target_version_for(check, target_version)
      check.targetable? ? target_version : nil
    end

    ##
    # No-op fix result for exact current-target requests.
    #
    # @param [Semverve::SemanticVersion, nil] target_version
    # @param [String] clean_message
    #
    # @return [Semverve::VersionAudit::FixResult]
    def noop_fix_result(target_version, clean_message)
      FixResult.new(
        current_version: current_version,
        target_version: target_version,
        groups: [],
        clean_message: clean_message,
        noop: true
      )
    end
  end
end
