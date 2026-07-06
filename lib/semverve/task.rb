# frozen_string_literal: true

require "rake"

require_relative "../semverve"
require_relative "generator"
require_relative "semantic_version"
require_relative "version_file"
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

        desc "Check configured files for stale version references"
        task :sync do
          sync
        end

        namespace :sync do
          desc "Replace stale version references in configured files"
          task :fix do
            fix_sync
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
    # Checks configured files for stale version references.
    #
    # @return [void]
    def sync
      configuration = Semverve.configuration.resolved
      current_version = VersionFile.new(configuration).current
      findings = VersionReferences.new(configuration, current_version).findings

      if findings.empty?
        puts "Version references are in sync."
        return
      end

      findings.each do |finding|
        puts "#{finding.path}:#{finding.line}:#{finding.column}: version reference #{finding.version} -> #{current_version}"
      end

      noun = findings.one? ? "reference" : "references"
      raise Error, "Found #{findings.count} version #{noun} out of sync."
    end

    ##
    # Replaces stale version references in configured files.
    #
    # @return [void]
    def fix_sync
      configuration = Semverve.configuration.resolved
      current_version = VersionFile.new(configuration).current
      result = VersionReferences.new(configuration, current_version).fix

      if result.replacement_count.zero?
        puts "Version references are in sync."
        return
      end

      result.changed_files.each { |path| puts "Updated #{path}" }
      noun = (result.replacement_count == 1) ? "reference" : "references"
      puts "Replaced #{result.replacement_count} version #{noun}."
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
