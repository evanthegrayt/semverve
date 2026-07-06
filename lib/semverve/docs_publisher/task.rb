# frozen_string_literal: true

require "rake"

require_relative "../docs_publisher"

module Semverve
  class DocsPublisher
    ##
    # Defines Rake tasks for publishing generated documentation.
    class Task
      include Rake::DSL

      ##
      # Source project root.
      #
      # @return [String]
      attr_accessor :root

      ##
      # Rake task that builds documentation before publishing.
      #
      # @return [String]
      attr_accessor :build_task

      ##
      # Directory containing generated documentation.
      #
      # @return [String]
      attr_accessor :source_dir

      ##
      # Documentation directory on the publishing branch.
      #
      # @return [String]
      attr_accessor :target_dir

      ##
      # Branch that receives generated documentation.
      #
      # @return [String]
      attr_accessor :branch

      ##
      # Remote used when pushing the publishing branch.
      #
      # @return [String]
      attr_accessor :remote

      ##
      # Commit message for generated documentation updates.
      #
      # @return [String]
      attr_accessor :commit_message

      ##
      # Optional path for the temporary worktree.
      #
      # @return [String, nil]
      attr_accessor :worktree_path

      ##
      # Whether dirty source working trees are allowed.
      #
      # @return [Boolean]
      attr_accessor :allow_dirty

      ##
      # Whether the publishing branch should be pushed.
      #
      # @return [Boolean]
      attr_accessor :push

      ##
      # Output stream for status messages.
      #
      # @return [#puts]
      attr_accessor :output

      ##
      # Namespace for the generated tasks.
      #
      # @return [Symbol, String]
      attr_accessor :task_namespace

      ##
      # Initializes and defines documentation publishing tasks.
      #
      # @yieldparam [Semverve::DocsPublisher::Task] task
      #
      # @return [Semverve::DocsPublisher::Task]
      def initialize
        @root = Dir.pwd
        @build_task = "rerdoc"
        @source_dir = "docs"
        @target_dir = "docs"
        @branch = "gh-pages"
        @remote = "origin"
        @commit_message = "Update generated documentation"
        @worktree_path = nil
        @allow_dirty = false
        @push = true
        @output = $stdout
        @task_namespace = :docs

        yield self if block_given?

        define
      end

      ##
      # Defines the documentation publishing tasks.
      #
      # @return [void]
      def define
        namespace namespace_name do
          desc "Publish generated documentation to #{branch}"
          task :publish do
            publish(dry_run: false)
          end

          namespace :publish do
            desc "Show whether generated documentation would change #{branch}"
            task :dry_run do
              publish(dry_run: true)
            end
          end
        end
      end

      private

      ##
      # Normalized namespace name.
      #
      # @return [Symbol]
      def namespace_name
        task_namespace.to_sym
      end

      ##
      # Builds and publishes documentation.
      #
      # @param [Boolean] dry_run
      #
      # @return [void]
      def publish(dry_run:)
        Rake::Task[build_task].invoke

        DocsPublisher.new do |publisher|
          publisher.root = root
          publisher.source_dir = source_dir
          publisher.target_dir = target_dir
          publisher.branch = branch
          publisher.remote = remote
          publisher.commit_message = commit_message
          publisher.worktree_path = worktree_path
          publisher.allow_dirty = allow_dirty
          publisher.push = push
          publisher.dry_run = dry_run
          publisher.output = output
        end.publish
      end
    end
  end
end
