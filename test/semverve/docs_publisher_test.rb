# frozen_string_literal: true

require "fileutils"
require "open3"
require "stringio"
require "tmpdir"

require_relative "../test_helper"
require_relative "../../lib/semverve/docs_publisher"
require_relative "../../lib/semverve/docs_publisher/task"

module Semverve
  class DocsPublisherTest < Test::Unit::TestCase
    def setup
      @tmpdir = Dir.mktmpdir
      @repo = File.join(@tmpdir, "repo")
      @remote = File.join(@tmpdir, "remote.git")
      @worktree = File.join(@tmpdir, "docs-worktree")
      FileUtils.mkdir_p(@repo)

      git("init", "--bare", @remote, chdir: @tmpdir)
      git("init", "--initial-branch=master", chdir: @repo)
      git("config", "user.email", "test@example.com", chdir: @repo)
      git("config", "user.name", "Test User", chdir: @repo)
      write_repo_file(".gitignore", "docs/*\n")
      write_repo_file("README.md", "Source branch\n")
      git("add", ".gitignore", "README.md", chdir: @repo)
      git("commit", "-m", "Initial source", chdir: @repo)

      git("checkout", "-b", "gh-pages", chdir: @repo)
      write_repo_file(".gitignore", "\n")
      write_repo_file(File.join("docs", "index.html"), "Old docs\n")
      git("add", ".gitignore", "docs", chdir: @repo)
      git("commit", "-m", "Initial docs", chdir: @repo)

      git("checkout", "master", chdir: @repo)
      git("remote", "add", "origin", @remote, chdir: @repo)
      git("push", "origin", "master", "gh-pages", chdir: @repo)
      write_repo_file(File.join("docs", "index.html"), "New docs\n")
    end

    def teardown
      FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
    end

    def test_publish_commits_and_pushes_generated_docs
      output = StringIO.new

      changed = publisher(output: output).publish

      assert_equal true, changed
      assert_equal "New docs\n", git("show", "gh-pages:docs/index.html", chdir: @repo)
      assert_match(/Published documentation to origin\/gh-pages\./, output.string)
      assert_equal "New docs\n", git("--git-dir", @remote, "show", "gh-pages:docs/index.html", chdir: @tmpdir)
      refute File.exist?(@worktree)
    end

    def test_publish_reports_when_docs_are_current
      output = StringIO.new
      publisher(output: output).publish
      output.truncate(0)
      output.rewind

      changed = publisher(output: output).publish

      assert_equal false, changed
      assert_equal "Documentation is already current on gh-pages.\n", output.string
    end

    def test_publish_can_create_local_branch_from_remote_tracking_branch
      git("branch", "-D", "gh-pages", chdir: @repo)

      changed = publisher.publish

      assert_equal true, changed
      assert_equal "New docs\n", git("show", "gh-pages:docs/index.html", chdir: @repo)
    end

    def test_publish_fails_when_publishing_branch_is_missing
      configured = publisher
      configured.branch = "missing-pages"

      error = assert_raise(Error) { configured.publish }

      assert_equal "Could not find missing-pages locally or at origin/missing-pages.", error.message
    end

    def test_dry_run_reports_changes_without_committing_or_pushing
      output = StringIO.new
      dry_run = publisher(output: output)
      dry_run.dry_run = true

      changed = dry_run.publish

      assert_equal true, changed
      assert_match(/dry run did not commit or push/, output.string)
      assert_equal "Old docs\n", git("show", "gh-pages:docs/index.html", chdir: @repo)
      assert_equal "Old docs\n", git("--git-dir", @remote, "show", "gh-pages:docs/index.html", chdir: @tmpdir)
    end

    def test_publish_refuses_dirty_source_worktree
      write_repo_file("README.md", "Dirty source branch\n")

      error = assert_raise(Error) { publisher.publish }

      assert_match(/Working tree must be clean/, error.message)
    end

    def test_publish_rejects_missing_source_directory
      configured = publisher
      configured.source_dir = "missing-docs"

      error = assert_raise(Error) { configured.publish }

      assert_match(/Documentation source directory does not exist/, error.message)
    end

    def test_publish_rejects_invalid_target_directory
      configured = publisher
      configured.target_dir = "."

      error = assert_raise(Error) { configured.publish }

      assert_equal "target_dir must be a relative directory such as \"docs\".", error.message
    end

    def test_publish_rejects_existing_explicit_worktree_path
      FileUtils.mkdir_p(@worktree)

      error = assert_raise(Error) { publisher.publish }

      assert_match(/Worktree path already exists/, error.message)
    end

    def test_publish_allows_dirty_source_worktree_when_configured
      write_repo_file("README.md", "Dirty source branch\n")
      configured = publisher
      configured.allow_dirty = true

      assert_equal true, configured.publish
    end

    def test_shell_reports_command_failures
      error = assert_raise(Error) do
        DocsPublisher::Shell.new.run(["git", "semverve-missing-subcommand"])
      end

      assert_match(/Command failed: git semverve-missing-subcommand/, error.message)
    end

    def test_rake_task_runs_build_task_and_publisher
      built = false

      with_rake_application do
        Rake::Task.define_task(:rerdoc) { built = true }
        DocsPublisher::Task.new do |task|
          task.root = @repo
          task.worktree_path = @worktree
          task.push = false
          task.output = StringIO.new
        end

        Rake::Task["docs:publish:dry_run"].invoke
      end

      assert_equal true, built
    end

    private

    def publisher(output: StringIO.new)
      DocsPublisher.new do |config|
        config.root = @repo
        config.worktree_path = @worktree
        config.output = output
      end
    end

    def write_repo_file(path, content)
      full_path = File.join(@repo, path)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)
    end

    def git(*arguments, chdir:)
      stdout, stderr, status = Open3.capture3("git", *arguments, chdir: chdir)
      raise "git #{arguments.join(" ")} failed: #{stderr}" unless status.success?

      stdout
    end

    def with_rake_application
      original_application = Rake.application
      Rake.application = Rake::Application.new
      yield
    ensure
      Rake.application = original_application
    end
  end

  class DocsPublisherTaskTest < Test::Unit::TestCase
    def setup
      @original_application = Rake.application
      Rake.application = Rake::Application.new
    end

    def teardown
      Rake.application = @original_application
    end

    def test_defines_docs_publish_tasks
      DocsPublisher::Task.new

      assert_not_nil Rake::Task["docs:publish"]
      assert_not_nil Rake::Task["docs:publish:dry_run"]
    end
  end
end
