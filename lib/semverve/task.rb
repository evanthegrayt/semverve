# frozen_string_literal: true

require "rake"

require_relative "../semverve"
require_relative "adapters"
require_relative "generator"
require_relative "published_version"
require_relative "semantic_version"
require_relative "version_file"
require_relative "version_checks"

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
          version_checks.each do |version_check|
            desc version_check.check_description
            task version_check.task_name, version_check.task_arguments do |_task, args|
              check_version_check(version_check, args)
            end
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
          version_checks.each do |version_check|
            desc version_check.fix_description
            task version_check.task_name, version_check.task_arguments do |_task, args|
              fix_version_check(version_check, args)
            end
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
    # Checks a single registered version check.
    #
    # @param [#findings] version_check
    # @param [Rake::TaskArguments, nil] args
    #
    # @return [void]
    def check_version_check(version_check, args = nil)
      configuration, current_version = check_context
      target_version = check_target_version(version_check, args, "semverve:check:#{version_check.task_name}")
      report_findings(
        [[
          version_check,
          version_check.finding_label,
          version_check.findings(
            configuration,
            current_version,
            include_ignored: report_ignored?,
            target_version: target_version
          )
        ]],
        current_version,
        target_version: target_version,
        fix_task_name: "semverve:fix:#{version_check.task_name}",
        clean_message: version_check.clean_message
      )
    end

    ##
    # Fixes a single registered version check.
    #
    # @param [#fix] version_check
    # @param [Rake::TaskArguments, nil] args
    #
    # @return [void]
    def fix_version_check(version_check, args = nil)
      configuration, current_version = check_context
      target_version = check_target_version(version_check, args, "semverve:fix:#{version_check.task_name}")
      return report_current_target_noop(target_version) if target_version == current_version

      report_fix_results(
        [[
          version_check.fix_label,
          version_check.fix(configuration, current_version, target_version: target_version)
        ]],
        clean_message: version_check.clean_message
      )
    end

    ##
    # Registered version checks available to tasks.
    #
    # @return [Array<#name>]
    def version_checks
      VersionChecks.all(extra_checks: Adapters.checks)
    end

    ##
    # Fetches a registered version check.
    #
    # @param [Symbol, String] name
    #
    # @return [#name]
    def version_check(name)
      VersionChecks.fetch(name, extra_checks: Adapters.checks)
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
    # @return [Array<Array(#name, String, Array)>]
    def check_groups(configuration, current_version, target_version = nil)
      configuration.version_checks.map do |check_name|
        version_check = version_check(check_name)
        [
          version_check,
          version_check.finding_label,
          version_check.findings(
            configuration,
            current_version,
            include_ignored: report_ignored?,
            target_version: target_version_for(version_check, target_version)
          )
        ]
      end
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
    # Optional exact version argument for checks that support targeting.
    #
    # @param [#targetable?] version_check
    # @param [Rake::TaskArguments, nil] args
    # @param [String] task_name
    #
    # @return [Semverve::SemanticVersion, nil]
    def check_target_version(version_check, args, task_name)
      return nil unless version_check.targetable?

      target_version_argument(args, task_name)
    end

    ##
    # Applies an umbrella target only to checks that support targeting.
    #
    # @param [#targetable?] version_check
    # @param [Semverve::SemanticVersion, nil] target_version
    #
    # @return [Semverve::SemanticVersion, nil]
    def target_version_for(version_check, target_version)
      version_check.targetable? ? target_version : nil
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
      configuration.version_checks.map do |check_name|
        version_check = version_check(check_name)
        [
          version_check.fix_label,
          version_check.fix(
            configuration,
            current_version,
            target_version: target_version_for(version_check, target_version)
          )
        ]
      end
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
      findings = groups.flat_map do |(version_check, label, group_findings)|
        group_findings.map { |finding| [version_check, label || finding.label, finding] }
      end

      if findings.empty?
        puts clean_message
        return
      end

      findings.each do |(_version_check, label, finding)|
        puts "#{finding.path}:#{finding.line}:#{finding.column}: #{label} #{finding.version} -> #{current_version}"
      end
      if target_version == current_version && fix_task_name && exact_target_fix_noop_findings?(findings)
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
    # Whether findings include surfaces controlled by exact-target fixes.
    #
    # @param [Array<Array(#exact_target_fix_noop_notice?, String, Object)>] findings
    #
    # @return [Boolean]
    def exact_target_fix_noop_findings?(findings)
      findings.any? { |(version_check, _label, _finding)| version_check.exact_target_fix_noop_notice? }
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
      bundle_lock_ran = results.any? { |(_label, result)| result.bundle_lock_ran }

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
