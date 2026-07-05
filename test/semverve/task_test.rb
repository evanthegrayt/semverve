# frozen_string_literal: true

require "fileutils"
require "stringio"
require "tmpdir"

require_relative "../test_helper"
require_relative "../../lib/semverve/task"

module Semverve
  class TaskTest < Test::Unit::TestCase
    def setup
      @original_application = Rake.application
      @original_directory = Dir.pwd
      @tmpdir = Dir.mktmpdir
      reset_configuration
      Rake.application = Rake::Application.new
    end

    def teardown
      Dir.chdir(@original_directory)
      Rake.application = @original_application
      FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
      reset_configuration
    end

    def test_defines_semverve_tasks
      in_project do
        write_gemspec("standup_md")
        write_module_version("StandupMD", "2.0.1")

        Task.new

        assert_not_nil Rake::Task["semverve:current"]
        assert_not_nil Rake::Task["semverve:increment:patch"]
        assert_not_nil Rake::Task["semverve:increment:minor"]
        assert_not_nil Rake::Task["semverve:increment:major"]
        assert_not_nil Rake::Task["semverve:generate"]
        assert_raise(RuntimeError) { Rake::Task["version:current"] }
      end
    end

    def test_current_reads_module_format
      in_project do
        write_gemspec("standup_md")
        write_module_version("StandupMD", "2.0.1")

        Task.new

        assert_equal "2.0.1\n", capture_stdout { Rake::Task["semverve:current"].invoke }
      end
    end

    def test_current_reads_simple_format
      in_project do
        write_gemspec("standup_md")
        write_simple_version("StandupMD", "2.0.1")

        Task.new { |config| config.format = :simple }

        assert_equal "2.0.1\n", capture_stdout { Rake::Task["semverve:current"].invoke }
      end
    end

    def test_increment_patch_updates_module_format
      in_project do
        write_gemspec("standup_md")
        path = write_module_version("StandupMD", "2.0.1")

        Task.new

        assert_equal "2.0.2\n", capture_stdout { Rake::Task["semverve:increment:patch"].invoke }
        assert_match(/PATCH = 2/, File.read(path))
      end
    end

    def test_increment_minor_updates_module_format
      in_project do
        write_gemspec("standup_md")
        path = write_module_version("StandupMD", "2.0.1")

        Task.new

        assert_equal "2.1.0\n", capture_stdout { Rake::Task["semverve:increment:minor"].invoke }
        assert_match(/MINOR = 1/, File.read(path))
        assert_match(/PATCH = 0/, File.read(path))
      end
    end

    def test_increment_major_updates_module_format
      in_project do
        write_gemspec("standup_md")
        path = write_module_version("StandupMD", "2.0.1")

        Task.new

        assert_equal "3.0.0\n", capture_stdout { Rake::Task["semverve:increment:major"].invoke }
        assert_match(/MAJOR = 3/, File.read(path))
        assert_match(/MINOR = 0/, File.read(path))
        assert_match(/PATCH = 0/, File.read(path))
      end
    end

    def test_increment_updates_simple_format
      in_project do
        write_gemspec("standup_md")
        path = write_simple_version("StandupMD", "2.0.1")

        Task.new { |config| config.format = :simple }

        assert_equal "2.0.2\n", capture_stdout { Rake::Task["semverve:increment:patch"].invoke }
        assert_match(/VERSION = "2.0.2"/, File.read(path))
      end
    end

    def test_bundle_lock_is_opt_in
      commands = []

      in_project do
        write_gemspec("standup_md")
        write_module_version("StandupMD", "2.0.1")

        Task.new do |config|
          config.command_runner = ->(command) { commands << command }
        end

        capture_stdout { Rake::Task["semverve:increment:patch"].invoke }

        assert_empty commands
      end
    end

    def test_bundle_lock_runs_when_enabled
      commands = []

      in_project do
        write_gemspec("standup_md")
        write_module_version("StandupMD", "2.0.1")

        Task.new do |config|
          config.bundle_lock = true
          config.command_runner = ->(command) { commands << command }
        end

        capture_stdout { Rake::Task["semverve:increment:patch"].invoke }

        assert_equal ["bundle lock"], commands
      end
    end

    def test_configuration_overrides_project_defaults
      in_project do
        write_gemspec("ignored_name")
        custom_path = File.join("custom", "version.rb")
        write_simple_version("CustomGem", "1.2.3", path: custom_path)

        Task.new do |config|
          config.gem_name = "custom_gem"
          config.module_name = "CustomGem"
          config.version_file = custom_path
          config.format = :simple
        end

        assert_equal "1.2.3\n", capture_stdout { Rake::Task["semverve:current"].invoke }
      end
    end

    def test_explicit_version_file_works_without_gemspec
      in_project do
        custom_path = File.join("custom", "version.rb")
        write_simple_version("CustomGem", "1.2.3", path: custom_path)

        Task.new do |config|
          config.version_file = custom_path
          config.module_name = "CustomGem"
          config.format = :simple
        end

        assert_equal "1.2.3\n", capture_stdout { Rake::Task["semverve:current"].invoke }
      end
    end

    def test_generate_defaults_to_module_format
      in_project do
        write_gemspec("standup_md")

        Task.new

        output = capture_stdout { Rake::Task["semverve:generate"].invoke }
        path = File.realpath(File.join(@tmpdir, "lib", "standup_md", "version.rb"))

        assert_match(/Generated #{Regexp.escape(path)}/, output)
        assert_match(/module StandupMd/, File.read(path))
        assert_match(/MAJOR = 0/, File.read(path))
        assert_match(/MINOR = 1/, File.read(path))
        assert_match(/PATCH = 0/, File.read(path))
      end
    end

    def test_generate_accepts_env_version_and_simple_format
      in_project do
        write_gemspec("standup_md")

        Task.new

        with_env("VERSION" => "1.2.3", "FORMAT" => "simple") do
          capture_stdout { Rake::Task["semverve:generate"].invoke }
        end

        assert_match(/VERSION = "1.2.3"/, File.read(File.join(@tmpdir, "lib", "standup_md", "version.rb")))
      end
    end

    def test_generate_fails_when_file_exists
      in_project do
        write_gemspec("standup_md")
        write_module_version("StandupMD", "2.0.1")

        Task.new

        error = assert_raise(Error) { Rake::Task["semverve:generate"].invoke }
        assert_match(/already exists/, error.message)
      end
    end

    def test_generate_can_force_overwrite
      in_project do
        write_gemspec("standup_md")
        path = write_module_version("StandupMD", "2.0.1")

        Task.new

        with_env("VERSION" => "1.2.3", "FORCE" => "true") do
          capture_stdout { Rake::Task["semverve:generate"].invoke }
        end

        assert_match(/MAJOR = 1/, File.read(path))
        assert_match(/MINOR = 2/, File.read(path))
        assert_match(/PATCH = 3/, File.read(path))
      end
    end

    def test_missing_gemspec_fails_without_override
      in_project do
        Task.new

        error = assert_raise(Error) { Rake::Task["semverve:current"].invoke }
        assert_match(/no .gemspec/, error.message)
      end
    end

    def test_multiple_gemspecs_fail_without_override
      in_project do
        write_gemspec("first")
        write_gemspec("second")

        Task.new

        error = assert_raise(Error) { Rake::Task["semverve:current"].invoke }
        assert_match(/multiple .gemspec/, error.message)
      end
    end

    def test_missing_version_file_fails_loudly
      in_project do
        write_gemspec("standup_md")

        Task.new

        error = assert_raise(Error) { Rake::Task["semverve:current"].invoke }
        assert_match(/Could not find version file/, error.message)
      end
    end

    def test_unparseable_version_file_fails_loudly
      in_project do
        write_gemspec("standup_md")
        write_file(File.join("lib", "standup_md", "version.rb"), "VERSION = \"nope\"\n")

        Task.new { |config| config.format = :simple }

        error = assert_raise(Error) { Rake::Task["semverve:current"].invoke }
        assert_match(/Could not parse/, error.message)
      end
    end

    def test_task_installation_is_idempotent
      in_project do
        write_gemspec("standup_md")
        write_module_version("StandupMD", "2.0.1")

        Task.new
        Task.new

        assert_equal 1, Rake.application.tasks.count { |task| task.name == "semverve:current" }
      end
    end

    private

    def in_project
      Dir.chdir(@tmpdir) { yield }
    end

    def reset_configuration
      Semverve.instance_variable_set(:@configuration, nil)
    end

    def write_gemspec(name)
      write_file("#{name}.gemspec", <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "#{name}"
        end
      RUBY
    end

    def write_module_version(module_name, version)
      parsed = SemanticVersion.parse(version)
      path = File.join("lib", underscore(module_name), "version.rb")

      write_file(path, Formats::ModuleConstants.new.generate(parsed, module_name: module_name))
      File.join(@tmpdir, path)
    end

    def write_simple_version(module_name, version, path: nil)
      path ||= File.join("lib", underscore(module_name), "version.rb")
      write_file(path, Formats::SimpleString.new.generate(SemanticVersion.parse(version), module_name: module_name))
      File.join(@tmpdir, path)
    end

    def write_file(path, content)
      full_path = File.join(@tmpdir, path)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)
      full_path
    end

    def underscore(value)
      value.gsub(/([a-z\d])([A-Z])/, "\\1_\\2").downcase
    end

    def capture_stdout
      original_stdout = $stdout
      output = StringIO.new
      $stdout = output
      yield
      output.string
    ensure
      $stdout = original_stdout
    end

    def with_env(values)
      original = values.each_with_object({}) do |(key, value), env|
        env[key] = ENV.fetch(key, nil)
        ENV[key] = value
      end

      yield
    ensure
      original.each do |key, value|
        if value.nil?
          ENV.delete(key)
        else
          ENV[key] = value
        end
      end
    end
  end
end
