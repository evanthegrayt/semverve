# frozen_string_literal: true

# TODO: Turn this into its own gem.

require "fileutils"
require "open3"
require "tmpdir"

require_relative "error"

module Semverve
  ##
  # Publishes generated documentation to a Git branch through a temporary
  # worktree.
  class DocsPublisher
    ##
    # Small command runner used by the publisher.
    class Shell
      ##
      # Runs a command and raises when it fails.
      #
      # @param [Array<String>] command
      # @param [String, nil] chdir
      #
      # @return [String]
      def run(command, chdir: nil)
        stdout, stderr, status = capture_command(command, chdir: chdir)
        return stdout if status.success?

        raise Error, "Command failed: #{command.join(" ")}\n#{stderr}"
      end

      ##
      # Captures a command's standard output and raises when it fails.
      #
      # @param [Array<String>] command
      # @param [String, nil] chdir
      #
      # @return [String]
      def capture(command, chdir: nil)
        run(command, chdir: chdir)
      end

      ##
      # Whether a command exits successfully.
      #
      # @param [Array<String>] command
      # @param [String, nil] chdir
      #
      # @return [Boolean]
      def success?(command, chdir: nil)
        _stdout, _stderr, status = capture_command(command, chdir: chdir)
        status.success?
      end

      private

      ##
      # Captures a command, omitting +chdir+ when none was provided.
      #
      # @param [Array<String>] command
      # @param [String, nil] chdir
      #
      # @return [Array(String, String, Process::Status)]
      def capture_command(command, chdir:)
        options = chdir ? {chdir: chdir} : {}

        Open3.capture3(*command, **options)
      end
    end

    ##
    # Source project root.
    #
    # @return [String]
    attr_accessor :root

    ##
    # Directory containing generated documentation, relative to +root+.
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
    # Whether to report changes without committing or pushing.
    #
    # @return [Boolean]
    attr_accessor :dry_run

    ##
    # Command runner used for Git commands.
    #
    # @return [#run, #capture, #success?]
    attr_accessor :command_runner

    ##
    # Output stream for status messages.
    #
    # @return [#puts]
    attr_accessor :output

    ##
    # Initializes a documentation publisher.
    #
    # @yieldparam [Semverve::DocsPublisher] publisher
    #
    # @return [Semverve::DocsPublisher]
    def initialize
      @root = Dir.pwd
      @source_dir = "docs"
      @target_dir = "docs"
      @branch = "gh-pages"
      @remote = "origin"
      @commit_message = "Update generated documentation"
      @worktree_path = nil
      @allow_dirty = false
      @push = true
      @dry_run = false
      @command_runner = Shell.new
      @output = $stdout

      yield self if block_given?
    end

    ##
    # Publishes generated documentation.
    #
    # @return [Boolean] whether documentation changes were found
    def publish
      validate!
      ensure_clean_source_worktree unless allow_dirty

      with_worktree do |worktree|
        sync_docs_to(worktree)

        unless publishing_worktree_changed?(worktree)
          output.puts "Documentation is already current on #{branch}."
          return false
        end

        if dry_run
          output.puts "Documentation changes detected for #{branch}; dry run did not commit or push."
          return true
        end

        commit_docs(worktree)
        push_docs(worktree) if push
        output.puts "Published documentation to #{remote}/#{branch}."
        true
      end
    end

    private

    ##
    # Validates publishing configuration.
    #
    # @return [void]
    def validate!
      raise Error, "Documentation source directory does not exist: #{source_path}." unless File.directory?(source_path)

      if target_dir.nil? || target_dir.empty? || target_dir == "." || target_dir.start_with?("/")
        raise Error, "target_dir must be a relative directory such as \"docs\"."
      end
    end

    ##
    # Absolute source project root.
    #
    # @return [String]
    def source_root
      @source_root ||= File.expand_path(root)
    end

    ##
    # Absolute source documentation directory.
    #
    # @return [String]
    def source_path
      File.expand_path(source_dir, source_root)
    end

    ##
    # Ensures the source working tree is clean.
    #
    # @return [void]
    def ensure_clean_source_worktree
      status = git_capture(source_root, "status", "--porcelain")
      return if status.empty?

      raise Error, "Working tree must be clean before publishing documentation. Commit, stash, or set allow_dirty."
    end

    ##
    # Yields a temporary publishing worktree and removes it afterward.
    #
    # @yieldparam [String] worktree
    #
    # @return [Object]
    def with_worktree
      temporary_path = worktree_path || Dir.mktmpdir("semverve-docs-publish-")
      temporary_worktree = worktree_path.nil?
      worktree_added = false

      if temporary_worktree
        FileUtils.rm_rf(temporary_path)
      elsif File.exist?(temporary_path)
        raise Error, "Worktree path already exists: #{temporary_path}."
      end

      add_worktree(temporary_path)
      worktree_added = true
      yield temporary_path
    ensure
      remove_worktree(temporary_path) if temporary_path && worktree_added
      FileUtils.rm_rf(temporary_path) if temporary_path && temporary_worktree
    end

    ##
    # Adds a worktree for the publishing branch.
    #
    # @param [String] path
    #
    # @return [void]
    def add_worktree(path)
      if local_branch?
        git_run(source_root, "worktree", "add", path, branch)
      elsif remote_branch?
        git_run(source_root, "worktree", "add", "-b", branch, path, "#{remote}/#{branch}")
      else
        raise Error, "Could not find #{branch} locally or at #{remote}/#{branch}."
      end
    end

    ##
    # Removes a worktree.
    #
    # @param [String] path
    #
    # @return [void]
    def remove_worktree(path)
      git_run(source_root, "worktree", "remove", "--force", path) if File.directory?(path)
    end

    ##
    # Whether the publishing branch exists locally.
    #
    # @return [Boolean]
    def local_branch?
      command_runner.success?(["git", "show-ref", "--verify", "--quiet", "refs/heads/#{branch}"], chdir: source_root)
    end

    ##
    # Whether the publishing branch exists as a remote-tracking branch.
    #
    # @return [Boolean]
    def remote_branch?
      command_runner.success?(["git", "show-ref", "--verify", "--quiet", "refs/remotes/#{remote}/#{branch}"], chdir: source_root)
    end

    ##
    # Copies generated documentation into the publishing worktree.
    #
    # @param [String] worktree
    #
    # @return [void]
    def sync_docs_to(worktree)
      target_path = File.expand_path(target_dir, worktree)

      FileUtils.rm_rf(target_path)
      FileUtils.mkdir_p(File.dirname(target_path))
      FileUtils.cp_r(source_path, target_path)
    end

    ##
    # Whether the publishing worktree has documentation changes.
    #
    # @param [String] worktree
    #
    # @return [Boolean]
    def publishing_worktree_changed?(worktree)
      !git_capture(worktree, "status", "--porcelain", "--", target_dir).empty?
    end

    ##
    # Commits documentation changes in the publishing worktree.
    #
    # @param [String] worktree
    #
    # @return [void]
    def commit_docs(worktree)
      git_run(worktree, "add", target_dir)
      git_run(worktree, "commit", "-m", commit_message)
    end

    ##
    # Pushes documentation changes.
    #
    # @param [String] worktree
    #
    # @return [void]
    def push_docs(worktree)
      git_run(worktree, "push", remote, branch)
    end

    ##
    # Runs a Git command in a directory.
    #
    # @param [String] directory
    # @param [Array<String>] arguments
    #
    # @return [String]
    def git_run(directory, *arguments)
      command_runner.run(["git", *arguments], chdir: directory)
    end

    ##
    # Captures a Git command in a directory.
    #
    # @param [String] directory
    # @param [Array<String>] arguments
    #
    # @return [String]
    def git_capture(directory, *arguments)
      command_runner.capture(["git", *arguments], chdir: directory)
    end
  end
end
