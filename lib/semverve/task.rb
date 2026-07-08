# frozen_string_literal: true

require "rake"

require_relative "../semverve"
require_relative "adapters"
require_relative "generator"
require_relative "published_version"
require_relative "semantic_version"
require_relative "task_reporter"
require_relative "version_audit"
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

      @task_namespace = Semverve.configuration.normalized_task_namespace

      unless self.class.send(:installed_for_current_application?)
        define
        self.class.send(:mark_current_application_installed)
      end
    end

    ##
    # Defines the configured Rake tasks.
    #
    # @return [void]
    def define
      namespace task_namespace do
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
    # Rake namespace used for installed task names.
    #
    # @return [String]
    attr_reader :task_namespace

    ##
    # Full Rake task name for user-facing messages.
    #
    # @param [Array<#to_s>] parts
    #
    # @return [String]
    def task_name(*parts)
      ([task_namespace] + parts).join(":")
    end

    ##
    # Increments a version level and reports the update.
    #
    # @param [Symbol] level
    #
    # @return [void]
    def increment(level)
      configuration = Semverve.configuration.resolved
      update = VersionFile.new(configuration).increment(level)

      reporter.report_update(update, configuration)
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

      reporter.report_update(update, configuration)
    end

    ##
    # Checks all version-maintenance surfaces.
    #
    # @return [void]
    def check(args = nil)
      target_version = target_version_argument(args, task_name("check"))
      reporter.report_check(audit(include_ignored: report_ignored?).check(target_version: target_version), fix_task_name: task_name("fix"))
    end

    ##
    # Fixes all check surfaces.
    #
    # @return [void]
    def fix(args = nil)
      target_version = target_version_argument(args, task_name("fix"))

      reporter.report_fix(audit.fix(target_version: target_version))
    end

    ##
    # Checks a single registered version check.
    #
    # @param [#findings] version_check
    # @param [Rake::TaskArguments, nil] args
    #
    # @return [void]
    def check_version_check(version_check, args = nil)
      target_version = target_version_argument(args, task_name("check", version_check.task_name))
      reporter.report_check(
        audit(include_ignored: report_ignored?).check_one(version_check.name, target_version: target_version),
        fix_task_name: task_name("fix", version_check.task_name)
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
      target_version = target_version_argument(args, task_name("fix", version_check.task_name))
      reporter.report_fix(audit.fix_one(version_check.name, target_version: target_version))
    end

    ##
    # Registered version checks available to tasks.
    #
    # @return [Array<#name>]
    def version_checks
      VersionChecks.all(extra_checks: Adapters.checks)
    end

    ##
    # Checks whether the current gem version is already published.
    #
    # @return [void]
    def check_rubygems
      configuration = Semverve.configuration.resolved
      current_version = VersionAudit.new(configuration: configuration).current_version
      PublishedVersion.new(configuration, current_version).check

      puts "#{configuration.gem_name} #{current_version} is not published on #{configuration.rubygems_host}."
    end

    ##
    # Checks configured release-readiness surfaces.
    #
    # @return [void]
    def check_release
      configuration = Semverve.configuration.resolved
      current_version = VersionAudit.new(configuration: configuration).current_version

      if configuration.release_checks.include?(:rubygems)
        PublishedVersion.new(configuration, current_version).check
      end

      puts "Release checks passed."
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
      raise Error, "Run rake '#{task_name("set")}[MAJOR.MINOR.PATCH]'." if version.nil? || version.empty?

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
    # Version audit for the current invocation.
    #
    # @return [Semverve::VersionAudit]
    def audit(include_ignored: false)
      VersionAudit.new(configuration: Semverve.configuration.resolved, include_ignored: include_ignored)
    end

    ##
    # Reporter for Rake output.
    #
    # @return [Semverve::TaskReporter]
    def reporter
      TaskReporter.new
    end
  end
end
