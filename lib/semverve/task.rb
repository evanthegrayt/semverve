# frozen_string_literal: true

require "rake"

require_relative "../semverve"
require_relative "generator"
require_relative "version_file"

module Semverve
  class Task
    include Rake::DSL

    class << self
      def install
        return if installed_for_current_application?

        new
      end

      private

      def installed_for_current_application?
        installed_applications.include?(Rake.application.object_id)
      end

      def installed_applications
        @installed_applications ||= []
      end

      def mark_current_application_installed
        installed_applications << Rake.application.object_id
      end
    end

    def initialize
      yield Semverve.configuration if block_given?

      unless self.class.send(:installed_for_current_application?)
        define
        self.class.send(:mark_current_application_installed)
      end
    end

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
      end
    end

    private

    def increment(level)
      configuration = Semverve.configuration.resolved
      next_version = VersionFile.new(configuration).increment(level)
      configuration.command_runner.call("bundle lock") if configuration.bundle_lock

      puts next_version
    end
  end
end

Semverve::Task.install
