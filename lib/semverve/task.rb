# frozen_string_literal: true

require "rake"

require_relative "../semverve"
require_relative "generator"
require_relative "published_version"
require_relative "semantic_version"
require_relative "version_file"
require_relative "version_code_references"
require_relative "version_metadata"
require_relative "version_references"

module Semverve
  ##
  # Defines Semverve's Rake tasks for the current Rake application.
  class Task
    include Rake::DSL

    class << self
      ##
      # Installs Semverve tasks once for the current Rake application.
      #
      # @return [Semverve::Task, nil]
      def install
        return if installed_for_current_application?

        new
      end

      private

      ##
      # Whether tasks were already installed for the current Rake application.
      #
      # @return [Boolean]
      def installed_for_current_application?
        installed_applications.include?(Rake.application.object_id)
      end

      ##
      # Rake application object IDs that already have Semverve tasks.
      #
      # @return [Array<Integer>]
      def installed_applications
        @installed_applications ||= []
      end

      ##
      # Records the current Rake application as installed.
      #
      # @return [Array<Integer>]
      def mark_current_application_installed
        installed_applications << Rake.application.object_id
      end
    end

    ##
    # Configures and defines Semverve tasks if needed.
    #
    # @yieldparam [Semverve::Configuration] configuration
    #
    # @return [Semverve::Task]
    def initialize
      yield Semverve.configuration if block_given?

      unless self.class.send(:installed_for_current_application?)
        define
        self.class.send(:mark_current_application_installed)
      end
    end

    ##
    # Defines the +semverve:*+ Rake tasks.
    #
    # @return [void]
    def define
      namespace :semverve do
        desc "Print the current version from the version.rb file"
        task :current do
          puts VersionFile.new(Semverve.configuration.resolved).current
        end

        namespace :increment do
          desc "Increment the version's PATCH level"
          task :patch do
            increment(:patch)
          end

          desc "Increment the version's MINOR level"
          task :minor do
            increment(:minor)
          end

          desc "Increment the version's MAJOR level"
          task :major do
            increment(:major)
          end
        end

        desc "Generate a version.rb file"
        task :generate, [:version, :format, :force] do |_task, args|
          generator_options = generate_options(args)
          puts "Generated #{Generator.new(
            Semverve.configuration.resolved,
            version: generator_options[:version],
            format: generator_options[:format],
            force: generator_options[:force]
          ).generate}"
        end

        desc "Set the version.rb file to version"
        task :set, [:version] do |_task, args|
          set(args)
        end

        desc "Check version references, code literals, and metadata"
        task :check, [:version] do |_task, args|
          check(args)
        end

        namespace :check do
          desc "Check configured files for stale version references"
          task :references, [:version] do |_task, args|
            check_references(args)
          end

          desc "Check configured code files for version literals"
          task :code, [:version] do |_task, args|
            check_code(args)
          end

          desc "Check gem metadata for version mismatches"
          task :metadata do
            check_metadata
          end

          desc "Check whether the current gem version is already published"
          task :rubygems do
            check_rubygems
          end

          desc "Check configured release-readiness surfaces"
          task :release do
            check_release
          end
        end

        desc "Fix version references, code literals, and metadata"
        task :fix, [:version] do |_task, args|
          fix(args)
        end

        namespace :fix do
          desc "Replace stale version references in configured files"
          task :references, [:version] do |_task, args|
            fix_references(args)
          end

          desc "Replace safe code version literals in configured files"
          task :code, [:version] do |_task, args|
            fix_code(args)
          end

          desc "Fix safe gem metadata version mismatches"
          task :metadata do
            fix_metadata
          end
        end
      end
    end

    private

    ##
    # Increments a version level and reports the update.
    #
    # @param [Symbol] level
    #
    # @return [void]
    def increment(level)
      configuration = Semverve.configuration.resolved
      update = VersionFile.new(configuration).increment(level)

      report(update, configuration)
    end

    ##
    # Sets the version to the value from the Rake +version+ argument.
    #
    # @param [Rake::TaskArguments] args
    #
    # @return [void]
    def set(args)
      configuration = Semverve.configuration.resolved
      requested_version = SemanticVersion.parse(requested_version_argument(args))
      update = VersionFile.new(configuration).set(requested_version)

      report(update, configuration)
    end

    ##
    # Checks all version-maintenance surfaces.
    #
    # @return [void]
    def check(args = nil)
      configuration, current_version = check_context
      target_version = target_version_argument(args, "semverve:check")
      report_findings(
        check_groups(configuration, current_version, target_version),
        current_version,
        target_version: target_version,
        fix_task_name: "semverve:fix",
        clean_message: "Version checks passed."
      )
    end

    ##
    # Fixes all check surfaces.
    #
    # @return [void]
    def fix(args = nil)
      configuration, current_version = check_context
      target_version = target_version_argument(args, "semverve:fix")
      return report_current_target_noop(target_version) if target_version == current_version

      report_fix_results(fix_results(configuration, current_version, target_version))
    end

    ##
    # Checks configured files for stale version references.
    #
    # @return [void]
    def check_references(args = nil)
      configuration, current_version = check_context
      target_version = target_version_argument(args, "semverve:check:references")
      report_findings(
        [[
          "version reference",
          VersionReferences.new(
            configuration,
            current_version,
            include_ignored: report_ignored?,
            target_version: target_version
          ).findings
        ]],
        current_version,
        target_version: target_version,
        fix_task_name: "semverve:fix:references",
        clean_message: "Version references are current."
      )
    end

    ##
    # Replaces stale version references in configured files.
    #
    # @return [void]
    def fix_references(args = nil)
      configuration, current_version = check_context
      target_version = target_version_argument(args, "semverve:fix:references")
      return report_current_target_noop(target_version) if target_version == current_version

      report_fix_results(
        [[
          "version reference",
          VersionReferences.new(configuration, current_version, target_version: target_version).fix
        ]],
        clean_message: "Version references are current."
      )
    end

    ##
    # Checks configured code files for version literals.
    #
    # @return [void]
    def check_code(args = nil)
      configuration, current_version = check_context
      target_version = target_version_argument(args, "semverve:check:code")
      report_findings(
        [[
          "code version literal",
          VersionCodeReferences.new(
            configuration,
            current_version,
            include_ignored: report_ignored?,
            target_version: target_version
          ).findings
        ]],
        current_version,
        target_version: target_version,
        fix_task_name: "semverve:fix:code",
        clean_message: "Code version literals are current."
      )
    end

    ##
    # Replaces safe code version literals in configured files.
    #
    # @return [void]
    def fix_code(args = nil)
      configuration, current_version = check_context
      target_version = target_version_argument(args, "semverve:fix:code")
      return report_current_target_noop(target_version) if target_version == current_version

      report_fix_results(
        [[
          "code version literal",
          VersionCodeReferences.new(configuration, current_version, target_version: target_version).fix
        ]],
        clean_message: "Code version literals are current."
      )
    end

    ##
    # Checks gem metadata for version mismatches.
    #
    # @return [void]
    def check_metadata
      configuration, current_version = check_context
      report_findings(
        [[nil, VersionMetadata.new(configuration, current_version).findings]],
        current_version,
        clean_message: "Version metadata is current."
      )
    end

    ##
    # Checks whether the current gem version is already published.
    #
    # @return [void]
    def check_rubygems
      configuration, current_version = check_context
      PublishedVersion.new(configuration, current_version).check

      puts "#{configuration.gem_name} #{current_version} is not published on #{configuration.rubygems_host}."
    end

    ##
    # Checks configured release-readiness surfaces.
    #
    # @return [void]
    def check_release
      configuration, current_version = check_context

      if configuration.release_checks.include?(:rubygems)
        PublishedVersion.new(configuration, current_version).check
      end

      puts "Release checks passed."
    end

    ##
    # Fixes safe gem metadata version mismatches.
    #
    # @return [void]
    def fix_metadata
      configuration, current_version = check_context
      report_fix_results(
        [["metadata version", VersionMetadata.new(configuration, current_version).fix]],
        clean_message: "Version metadata is current."
      )
    end

    ##
    # Resolved configuration and current version for check tasks.
    #
    # @return [Array(Semverve::ResolvedConfiguration, Semverve::SemanticVersion)]
    def check_context
      configuration = Semverve.configuration.resolved
      [configuration, VersionFile.new(configuration).current]
    end

    ##
    # Finding groups enabled for the umbrella check task.
    #
    # @param [Semverve::ResolvedConfiguration] configuration
    # @param [Semverve::SemanticVersion] current_version
    #
    # @param [Semverve::SemanticVersion, nil] target_version
    #
    # @return [Array<Array(String, Array)>]
    def check_groups(configuration, current_version, target_version = nil)
      groups = []
      if configuration.version_checks.include?(:doc_references)
        groups << [
          "version reference",
          VersionReferences.new(
            configuration,
            current_version,
            include_ignored: report_ignored?,
            target_version: target_version
          ).findings
        ]
      end
      if configuration.version_checks.include?(:code_references)
        groups << [
          "code version literal",
          VersionCodeReferences.new(
            configuration,
            current_version,
            include_ignored: report_ignored?,
            target_version: target_version
          ).findings
        ]
      end
      if configuration.version_checks.include?(:metadata)
        groups << [nil, VersionMetadata.new(configuration, current_version).findings]
      end
      groups
    end

    ##
    # Whether check tasks should report references hidden by ignore markers.
    #
    # @return [Boolean]
    def report_ignored?
      ENV.fetch("SEMVERVE_REPORT_IGNORED", "false").match?(/\A(true|1|yes)\z/i)
    end

    ##
    # Parsed arguments for +semverve:generate+.
    #
    # @param [Rake::TaskArguments] args
    #
    # @return [Hash]
    def generate_options(args)
      args.to_a.each_with_object({force: false}) do |value, options|
        assign_generate_option(value, options)
      end
    end

    ##
    # Assigns a single +semverve:generate+ token by meaning.
    #
    # @param [String] value
    # @param [Hash] options
    #
    # @return [void]
    def assign_generate_option(value, options)
      case value
      when nil, ""
        nil
      when "force"
        raise Error, "Duplicate generate option force." if options[:force]

        options[:force] = true
      when SemanticVersion::PATTERN
        raise Error, "Duplicate generate version #{value.inspect}." if options[:version]

        options[:version] = value
      when "module", "simple"
        raise Error, "Duplicate generate format #{value.inspect}." if options[:format]

        options[:format] = value
      else
        raise Error, "Unknown generate option #{value.inspect}. Use a semantic version, module, simple, or force."
      end
    end

    ##
    # Required version argument for +semverve:set+.
    #
    # @param [Rake::TaskArguments] args
    #
    # @return [String]
    def requested_version_argument(args)
      version = args[:version]
      raise Error, "Run rake 'semverve:set[MAJOR.MINOR.PATCH]'." if version.nil? || version.empty?

      version
    end

    ##
    # Optional exact version argument for check and fix tasks.
    #
    # @param [Rake::TaskArguments, nil] args
    # @param [String] task_name
    #
    # @return [Semverve::SemanticVersion, nil]
    def target_version_argument(args, task_name)
      version = args&.[](:version)
      return nil if version.nil? || version.empty?

      SemanticVersion.parse(version)
    rescue Error
      raise Error, "Run rake '#{task_name}[MAJOR.MINOR.PATCH]'."
    end

    ##
    # Fix results enabled for the umbrella fix task.
    #
    # @param [Semverve::ResolvedConfiguration] configuration
    # @param [Semverve::SemanticVersion] current_version
    # @param [Semverve::SemanticVersion, nil] target_version
    #
    # @return [Array<Array(String, #replacement_count, #changed_files)>]
    def fix_results(configuration, current_version, target_version = nil)
      results = []
      if configuration.version_checks.include?(:doc_references)
        results << [
          "version reference",
          VersionReferences.new(configuration, current_version, target_version: target_version).fix
        ]
      end
      if configuration.version_checks.include?(:code_references)
        results << [
          "code version literal",
          VersionCodeReferences.new(configuration, current_version, target_version: target_version).fix
        ]
      end
      if configuration.version_checks.include?(:metadata)
        results << ["metadata version", VersionMetadata.new(configuration, current_version).fix]
      end
      results
    end

    ##
    # Prints findings and raises when mismatches exist.
    #
    # @param [Array<Array(String, Array)>] groups
    # @param [Semverve::SemanticVersion] current_version
    # @param [Semverve::SemanticVersion, nil] target_version
    # @param [String, nil] fix_task_name
    # @param [String] clean_message
    #
    # @return [void]
    def report_findings(groups, current_version, clean_message:, target_version: nil, fix_task_name: nil)
      findings = groups.flat_map do |(label, group_findings)|
        group_findings.map { |finding| [label || finding.label, finding] }
      end

      if findings.empty?
        puts clean_message
        return
      end

      findings.each do |(label, finding)|
        puts "#{finding.path}:#{finding.line}:#{finding.column}: #{label} #{finding.version} -> #{current_version}"
      end
      if target_version == current_version && fix_task_name && reference_or_code_findings?(findings)
        puts "Target version #{target_version} is already current; #{fix_task_name}[#{target_version}] will not change these references."
      end

      issue = findings.one? ? "issue" : "issues"
      raise Error, "Found #{findings.count} version check #{issue}."
    end

    ##
    # Prints a no-op message for exact fix requests targeting the current version.
    #
    # @param [Semverve::SemanticVersion, nil] target_version
    #
    # @return [void]
    def report_current_target_noop(target_version)
      puts "Target version #{target_version} is already current; nothing to fix."
    end

    ##
    # Whether findings include references controlled by exact-target fixes.
    #
    # @param [Array<Array(String, Object)>] findings
    #
    # @return [Boolean]
    def reference_or_code_findings?(findings)
      findings.any? do |(label, _finding)|
        ["version reference", "code version literal"].include?(label)
      end
    end

    ##
    # Prints fix results.
    #
    # @param [Array<Array(String, #replacement_count, #changed_files)>] results
    # @param [String] clean_message
    #
    # @return [void]
    def report_fix_results(results, clean_message: "Version checks passed.")
      replacement_count = results.sum { |(_label, result)| result.replacement_count }
      bundle_lock_ran = results.any? { |(_label, result)| result.respond_to?(:bundle_lock_ran) && result.bundle_lock_ran }

      if replacement_count.zero? && !bundle_lock_ran
        puts clean_message
        return
      end

      results.each do |(label, result)|
        result.changed_files.each { |path| puts "Updated #{path}" }
        next if result.replacement_count.zero?

        noun = (result.replacement_count == 1) ? label : "#{label}s"
        puts "Replaced #{result.replacement_count} #{noun}."
      end

      puts "Ran bundle lock." if bundle_lock_ran
    end

    ##
    # Reports an update and runs configured follow-up commands.
    #
    # @param [Semverve::VersionFile::UpdateResult] update
    # @param [Semverve::ResolvedConfiguration] configuration
    #
    # @return [void]
    def report(update, configuration)
      unless update.changed?
        puts "Version is already #{update.version}"
        return
      end

      if update.version < update.previous_version
        warn "Warning: updating to version #{update.version}, which is lower than the current version #{update.previous_version}."
      end

      puts "Updating to version #{update.version} (was #{update.previous_version})"
      configuration.command_runner.call("bundle lock") if configuration.bundle_lock
    end
  end
end

Semverve::Task.install
