# frozen_string_literal: true

require "rake"

require_relative "../semverve"
require_relative "generator"
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
        task :generate do
          puts "Generated #{Generator.new(Semverve.configuration.resolved).generate}"
        end

        desc "Set the version.rb file to VERSION"
        task :set do
          set
        end

        desc "Check version references, code literals, and metadata"
        task :sync do
          sync
        end

        namespace :sync do
          desc "Fix version references, code literals, and metadata"
          task :fix do
            fix_sync
          end

          desc "Check configured files for stale version references"
          task :references do
            sync_references
          end

          namespace :references do
            desc "Replace stale version references in configured files"
            task :fix do
              fix_references
            end
          end

          desc "Check configured code files for version literals"
          task :code do
            sync_code
          end

          namespace :code do
            desc "Replace safe code version literals in configured files"
            task :fix do
              fix_code
            end
          end

          desc "Check gem metadata for version mismatches"
          task :metadata do
            sync_metadata
          end

          namespace :metadata do
            desc "Fix safe gem metadata version mismatches"
            task :fix do
              fix_metadata
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
    # Sets the version to the value from the +VERSION+ environment variable.
    #
    # @return [void]
    def set
      configuration = Semverve.configuration.resolved
      requested_version = SemanticVersion.parse(
        ENV.fetch("VERSION") { raise Error, "Set VERSION=MAJOR.MINOR.PATCH." }
      )
      update = VersionFile.new(configuration).set(requested_version)

      report(update, configuration)
    end

    ##
    # Checks all sync surfaces.
    #
    # @return [void]
    def sync
      configuration, current_version = sync_context
      report_findings(
        [
          ["version reference", VersionReferences.new(configuration, current_version).findings],
          ["code version literal", VersionCodeReferences.new(configuration, current_version).findings],
          [nil, VersionMetadata.new(configuration, current_version).findings]
        ],
        current_version,
        clean_message: "Version sync checks passed."
      )
    end

    ##
    # Fixes all sync surfaces.
    #
    # @return [void]
    def fix_sync
      configuration, current_version = sync_context
      results = [
        ["version reference", VersionReferences.new(configuration, current_version).fix],
        ["code version literal", VersionCodeReferences.new(configuration, current_version).fix],
        ["metadata version", VersionMetadata.new(configuration, current_version).fix]
      ]

      report_fix_results(results)
    end

    ##
    # Checks configured files for stale version references.
    #
    # @return [void]
    def sync_references
      configuration, current_version = sync_context
      report_findings(
        [["version reference", VersionReferences.new(configuration, current_version).findings]],
        current_version,
        clean_message: "Version references are in sync."
      )
    end

    ##
    # Replaces stale version references in configured files.
    #
    # @return [void]
    def fix_references
      configuration, current_version = sync_context
      report_fix_results(
        [["version reference", VersionReferences.new(configuration, current_version).fix]],
        clean_message: "Version references are in sync."
      )
    end

    ##
    # Checks configured code files for version literals.
    #
    # @return [void]
    def sync_code
      configuration, current_version = sync_context
      report_findings(
        [["code version literal", VersionCodeReferences.new(configuration, current_version).findings]],
        current_version,
        clean_message: "Code version literals are in sync."
      )
    end

    ##
    # Replaces safe code version literals in configured files.
    #
    # @return [void]
    def fix_code
      configuration, current_version = sync_context
      report_fix_results(
        [["code version literal", VersionCodeReferences.new(configuration, current_version).fix]],
        clean_message: "Code version literals are in sync."
      )
    end

    ##
    # Checks gem metadata for version mismatches.
    #
    # @return [void]
    def sync_metadata
      configuration, current_version = sync_context
      report_findings(
        [[nil, VersionMetadata.new(configuration, current_version).findings]],
        current_version,
        clean_message: "Version metadata is in sync."
      )
    end

    ##
    # Fixes safe gem metadata version mismatches.
    #
    # @return [void]
    def fix_metadata
      configuration, current_version = sync_context
      report_fix_results(
        [["metadata version", VersionMetadata.new(configuration, current_version).fix]],
        clean_message: "Version metadata is in sync."
      )
    end

    ##
    # Resolved configuration and current version for sync tasks.
    #
    # @return [Array(Semverve::ResolvedConfiguration, Semverve::SemanticVersion)]
    def sync_context
      configuration = Semverve.configuration.resolved
      [configuration, VersionFile.new(configuration).current]
    end

    ##
    # Prints findings and raises when mismatches exist.
    #
    # @param [Array<Array(String, Array)>] groups
    # @param [Semverve::SemanticVersion] current_version
    # @param [String] clean_message
    #
    # @return [void]
    def report_findings(groups, current_version, clean_message:)
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

      issue = findings.one? ? "issue" : "issues"
      raise Error, "Found #{findings.count} version sync #{issue}."
    end

    ##
    # Prints fix results.
    #
    # @param [Array<Array(String, #replacement_count, #changed_files)>] results
    # @param [String] clean_message
    #
    # @return [void]
    def report_fix_results(results, clean_message: "Version sync checks passed.")
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
