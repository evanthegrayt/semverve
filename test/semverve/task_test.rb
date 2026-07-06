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
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")

        Task.new

        assert_not_nil Rake::Task["semverve:current"]
        assert_not_nil Rake::Task["semverve:set"]
        assert_not_nil Rake::Task["semverve:increment:patch"]
        assert_not_nil Rake::Task["semverve:increment:minor"]
        assert_not_nil Rake::Task["semverve:increment:major"]
        assert_not_nil Rake::Task["semverve:generate"]
        assert_not_nil Rake::Task["semverve:sync"]
        assert_not_nil Rake::Task["semverve:sync:fix"]
        assert_not_nil Rake::Task["semverve:sync:references"]
        assert_not_nil Rake::Task["semverve:sync:references:fix"]
        assert_not_nil Rake::Task["semverve:sync:code"]
        assert_not_nil Rake::Task["semverve:sync:code:fix"]
        assert_not_nil Rake::Task["semverve:sync:metadata"]
        assert_not_nil Rake::Task["semverve:sync:metadata:fix"]
        assert_raise(RuntimeError) { Rake::Task["version:current"] }
      end
    end

    def test_current_reads_module_format
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")

        Task.new

        assert_equal "2.0.1\n", capture_stdout { Rake::Task["semverve:current"].invoke }
      end
    end

    def test_current_reads_simple_format
      in_project do
        write_gemspec("my_gem")
        write_simple_version("MyGem", "2.0.1")

        Task.new { |config| config.format = :simple }

        assert_equal "2.0.1\n", capture_stdout { Rake::Task["semverve:current"].invoke }
      end
    end

    def test_increment_patch_updates_module_format
      in_project do
        write_gemspec("my_gem")
        path = write_module_version("MyGem", "2.0.1")

        Task.new

        assert_equal "Updating to version 2.0.2 (was 2.0.1)\n", capture_stdout { Rake::Task["semverve:increment:patch"].invoke }
        assert_match(/PATCH = 2/, File.read(path))
      end
    end

    def test_increment_minor_updates_module_format
      in_project do
        write_gemspec("my_gem")
        path = write_module_version("MyGem", "2.0.1")

        Task.new

        assert_equal "Updating to version 2.1.0 (was 2.0.1)\n", capture_stdout { Rake::Task["semverve:increment:minor"].invoke }
        assert_match(/MINOR = 1/, File.read(path))
        assert_match(/PATCH = 0/, File.read(path))
      end
    end

    def test_increment_major_updates_module_format
      in_project do
        write_gemspec("my_gem")
        path = write_module_version("MyGem", "2.0.1")

        Task.new

        assert_equal "Updating to version 3.0.0 (was 2.0.1)\n", capture_stdout { Rake::Task["semverve:increment:major"].invoke }
        assert_match(/MAJOR = 3/, File.read(path))
        assert_match(/MINOR = 0/, File.read(path))
        assert_match(/PATCH = 0/, File.read(path))
      end
    end

    def test_increment_updates_simple_format
      in_project do
        write_gemspec("my_gem")
        path = write_simple_version("MyGem", "2.0.1")

        Task.new { |config| config.format = :simple }

        assert_equal "Updating to version 2.0.2 (was 2.0.1)\n", capture_stdout { Rake::Task["semverve:increment:patch"].invoke }
        assert_match(/VERSION = "2.0.2"/, File.read(path))
      end
    end

    def test_set_updates_module_format
      in_project do
        write_gemspec("my_gem")
        path = write_module_version("MyGem", "2.0.1")

        Task.new

        stdout = with_env("VERSION" => "2.3.4") do
          capture_stdout { Rake::Task["semverve:set"].invoke }
        end

        assert_equal "Updating to version 2.3.4 (was 2.0.1)\n", stdout
        assert_match(/MAJOR = 2/, File.read(path))
        assert_match(/MINOR = 3/, File.read(path))
        assert_match(/PATCH = 4/, File.read(path))
      end
    end

    def test_set_updates_simple_format
      in_project do
        write_gemspec("my_gem")
        path = write_simple_version("MyGem", "2.0.1")

        Task.new { |config| config.format = :simple }

        stdout = with_env("VERSION" => "2.3.4") do
          capture_stdout { Rake::Task["semverve:set"].invoke }
        end

        assert_equal "Updating to version 2.3.4 (was 2.0.1)\n", stdout
        assert_match(/VERSION = "2.3.4"/, File.read(path))
      end
    end

    def test_set_fails_without_version
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")

        Task.new

        error = assert_raise(Error) { Rake::Task["semverve:set"].invoke }
        assert_equal "Set VERSION=MAJOR.MINOR.PATCH.", error.message
      end
    end

    def test_set_fails_with_invalid_version
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")

        Task.new

        error = with_env("VERSION" => "nope") do
          assert_raise(Error) { Rake::Task["semverve:set"].invoke }
        end

        assert_match(/Expected a semantic version/, error.message)
      end
    end

    def test_set_lower_version_warns_and_updates
      in_project do
        write_gemspec("my_gem")
        path = write_module_version("MyGem", "2.0.1")

        Task.new

        stdout, stderr = with_env("VERSION" => "1.9.9") do
          capture_output { Rake::Task["semverve:set"].invoke }
        end

        assert_equal "Updating to version 1.9.9 (was 2.0.1)\n", stdout
        assert_equal "Warning: updating to version 1.9.9, which is lower than the current version 2.0.1.\n", stderr
        assert_match(/MAJOR = 1/, File.read(path))
        assert_match(/MINOR = 9/, File.read(path))
        assert_match(/PATCH = 9/, File.read(path))
      end
    end

    def test_set_same_version_is_noop
      commands = []

      in_project do
        write_gemspec("my_gem")
        path = write_module_version("MyGem", "2.0.1")
        original_content = File.read(path)

        Task.new do |config|
          config.bundle_lock = true
          config.command_runner = ->(command) { commands << command }
        end

        stdout, stderr = with_env("VERSION" => "2.0.1") do
          capture_output { Rake::Task["semverve:set"].invoke }
        end

        assert_equal "Version is already 2.0.1\n", stdout
        assert_empty stderr
        assert_equal original_content, File.read(path)
        assert_empty commands
      end
    end

    def test_set_runs_bundle_lock_when_enabled
      commands = []

      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")

        Task.new do |config|
          config.bundle_lock = true
          config.command_runner = ->(command) { commands << command }
        end

        with_env("VERSION" => "2.0.2") do
          capture_stdout { Rake::Task["semverve:set"].invoke }
        end

        assert_equal ["bundle lock"], commands
      end
    end

    def test_bundle_lock_is_opt_in
      commands = []

      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")

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
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")

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
        write_gemspec("my_gem")

        Task.new

        output = capture_stdout { Rake::Task["semverve:generate"].invoke }
        path = File.realpath(File.join(@tmpdir, "lib", "my_gem", "version.rb"))

        assert_match(/Generated #{Regexp.escape(path)}/, output)
        assert_match(/module MyGem/, File.read(path))
        assert_match(/MAJOR = 0/, File.read(path))
        assert_match(/MINOR = 1/, File.read(path))
        assert_match(/PATCH = 0/, File.read(path))
      end
    end

    def test_generate_accepts_env_version_and_simple_format
      in_project do
        write_gemspec("my_gem")

        Task.new

        with_env("VERSION" => "1.2.3", "FORMAT" => "simple") do
          capture_stdout { Rake::Task["semverve:generate"].invoke }
        end

        assert_match(/VERSION = "1.2.3"/, File.read(File.join(@tmpdir, "lib", "my_gem", "version.rb")))
      end
    end

    def test_generate_fails_when_file_exists
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")

        Task.new

        error = assert_raise(Error) { Rake::Task["semverve:generate"].invoke }
        assert_match(/already exists/, error.message)
      end
    end

    def test_generate_can_force_overwrite
      in_project do
        write_gemspec("my_gem")
        path = write_module_version("MyGem", "2.0.1")

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
        write_gemspec("my_gem")

        Task.new

        error = assert_raise(Error) { Rake::Task["semverve:current"].invoke }
        assert_match(/Could not find version file/, error.message)
      end
    end

    def test_unparseable_version_file_fails_loudly
      in_project do
        write_gemspec("my_gem")
        write_file(File.join("lib", "my_gem", "version.rb"), "VERSION = \"nope\"\n")

        Task.new { |config| config.format = :simple }

        error = assert_raise(Error) { Rake::Task["semverve:current"].invoke }
        assert_match(/Could not parse/, error.message)
      end
    end

    def test_task_installation_is_idempotent
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")

        Task.new
        Task.new

        assert_equal 1, Rake.application.tasks.count { |task| task.name == "semverve:current" }
      end
    end

    def test_sync_scans_readme_files_by_default
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Install version 2.0.0.\n")
        write_file(File.join("guides", "README.md"), "Upgrade from 1.9.9.\n")
        write_file(File.join("doc", "usage.md"), "Generated docs mention 1.0.0.\n")

        Task.new

        stdout, stderr, error = capture_error(Error) { Rake::Task["semverve:sync:references"].invoke }

        assert_match(/README\.md:1:17: version reference 2\.0\.0 -> 2\.0\.1/, stdout)
        assert_match(%r{guides/README\.md:1:14: version reference 1\.9\.9 -> 2\.0\.1}, stdout)
        assert_no_match(/doc\/usage\.md/, stdout)
        assert_equal "Found 2 version sync issues.", error.message
        assert_empty stderr
      end
    end

    def test_sync_can_append_to_default_doc_reference_files
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Install version 2.0.0.\n")
        write_file(File.join("doc", "usage.md"), "Documented as 1.0.0.\n")

        Task.new do |config|
          config.version_doc_reference_files.append("doc/**/*.md")
        end

        stdout, = capture_error(Error) { Rake::Task["semverve:sync:references"].invoke }

        assert_match(/README\.md:1:17: version reference 2\.0\.0 -> 2\.0\.1/, stdout)
        assert_match(%r{doc/usage\.md:1:15: version reference 1\.0\.0 -> 2\.0\.1}, stdout)
      end
    end

    def test_sync_can_replace_default_doc_reference_files
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Install version 2.0.0.\n")
        write_file(File.join("guides", "usage.md"), "Documented as 1.0.0.\n")

        Task.new do |config|
          config.version_doc_reference_files = Rake::FileList["guides/**/*.md"]
        end

        stdout, = capture_error(Error) { Rake::Task["semverve:sync:references"].invoke }

        assert_no_match(/README\.md/, stdout)
        assert_match(%r{guides/usage\.md:1:15: version reference 1\.0\.0 -> 2\.0\.1}, stdout)
      end
    end

    def test_sync_defaults_to_older_version_references
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Old 2.0.0, current 2.0.1, future 2.0.2.\n")

        Task.new

        stdout, = capture_error(Error) { Rake::Task["semverve:sync:references"].invoke }

        assert_match(/README\.md:1:5: version reference 2\.0\.0 -> 2\.0\.1/, stdout)
        assert_no_match(/2\.0\.2 -> 2\.0\.1/, stdout)
      end
    end

    def test_sync_can_report_non_current_version_references
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Old 2.0.0, current 2.0.1, future 2.0.2.\n")

        Task.new do |config|
          config.version_reference_mode = :non_current
        end

        stdout, = capture_error(Error) { Rake::Task["semverve:sync:references"].invoke }

        assert_match(/README\.md:1:5: version reference 2\.0\.0 -> 2\.0\.1/, stdout)
        assert_match(/README\.md:1:34: version reference 2\.0\.2 -> 2\.0\.1/, stdout)
        assert_no_match(/current 2\.0\.1 -> 2\.0\.1/, stdout)
      end
    end

    def test_sync_scans_ruby_comments_without_scanning_code_literals
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file(File.join("lib", "my_gem", "example.rb"), <<~RUBY)
          EXAMPLE_VERSION = "1.0.0"
          # See version 1.0.0.
        RUBY

        Task.new do |config|
          config.version_doc_reference_files = Rake::FileList["lib/**/*.rb"]
        end

        stdout, = capture_error(Error) { Rake::Task["semverve:sync:references"].invoke }

        assert_no_match(/1:20/, stdout)
        assert_match(%r{lib/my_gem/example\.rb:2:15: version reference 1\.0\.0 -> 2\.0\.1}, stdout)
      end
    end

    def test_sync_fix_replaces_version_references
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        readme_path = write_file("README.md", "Install version 2.0.0.\n")
        example_path = write_file(File.join("lib", "my_gem", "example.rb"), <<~RUBY)
          EXAMPLE_VERSION = "1.0.0"
          # See version 1.0.0.
        RUBY

        Task.new do |config|
          config.version_doc_reference_files.append("lib/**/*.rb")
        end

        stdout = capture_stdout { Rake::Task["semverve:sync:references:fix"].invoke }

        assert_match(/Updated README\.md/, stdout)
        assert_match(%r{Updated lib/my_gem/example\.rb}, stdout)
        assert_match(/Replaced 2 version references\./, stdout)
        assert_equal "Install version 2.0.1.\n", File.read(readme_path)
        assert_match(/EXAMPLE_VERSION = "1\.0\.0"/, File.read(example_path))
        assert_match(/# See version 2\.0\.1\./, File.read(example_path))
      end
    end

    def test_sync_honors_inline_ignore_markers
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", <<~MARKDOWN)
          Same line 1.0.0. <!-- semverve:ignore-version-reference -->
          <!-- semverve:ignore-version-reference -->

          Previous marker ignores 1.5.0.
          Report this 1.9.9.
        MARKDOWN

        Task.new

        stdout, = capture_error(Error) { Rake::Task["semverve:sync:references"].invoke }

        assert_no_match(/1\.0\.0/, stdout)
        assert_no_match(/1\.5\.0/, stdout)
        assert_match(/README\.md:5:13: version reference 1\.9\.9 -> 2\.0\.1/, stdout)
      end
    end

    def test_sync_reports_clean_doc_reference_files
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Install version 2.0.1.\n")

        Task.new

        assert_equal "Version references are in sync.\n", capture_stdout { Rake::Task["semverve:sync:references"].invoke }
      end
    end

    def test_sync_code_reports_safe_version_literals
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file(File.join("lib", "my_gem", "constants.rb"), <<~RUBY)
          APP_VERSION = "2.0.0"
          EXAMPLE = "1.0.0"
        RUBY

        Task.new do |config|
          config.version_code_reference_files = Rake::FileList["lib/**/*.rb"]
        end

        stdout, = capture_error(Error) { Rake::Task["semverve:sync:code"].invoke }

        assert_match(%r{lib/my_gem/constants\.rb:1:16: code version literal 2\.0\.0 -> 2\.0\.1}, stdout)
        assert_no_match(/1\.0\.0/, stdout)
      end
    end

    def test_sync_code_fix_replaces_safe_version_literals
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        path = write_file(File.join("lib", "my_gem", "constants.rb"), <<~RUBY)
          APP_VERSION = "2.0.0"
          EXAMPLE = "1.0.0"
        RUBY

        Task.new do |config|
          config.version_code_reference_files = Rake::FileList["lib/**/*.rb"]
        end

        stdout = capture_stdout { Rake::Task["semverve:sync:code:fix"].invoke }

        assert_match(%r{Updated lib/my_gem/constants\.rb}, stdout)
        assert_match(/Replaced 1 code version literal\./, stdout)
        assert_match(/APP_VERSION = "2\.0\.1"/, File.read(path))
        assert_match(/EXAMPLE = "1\.0\.0"/, File.read(path))
      end
    end

    def test_sync_metadata_reports_literal_gemspec_mismatch
      in_project do
        write_gemspec("my_gem", version: "2.0.0")
        write_module_version("MyGem", "2.0.1")

        Task.new

        stdout, = capture_error(Error) { Rake::Task["semverve:sync:metadata"].invoke }

        assert_match(/my_gem\.gemspec:\d+:\d+: gemspec version 2\.0\.0 -> 2\.0\.1/, stdout)
      end
    end

    def test_sync_metadata_reports_lockfile_mismatch
      in_project do
        write_gemspec("my_gem", version: "2.0.1")
        write_module_version("MyGem", "2.0.1")
        write_lockfile("my_gem", "2.0.0")

        Task.new

        stdout, = capture_error(Error) { Rake::Task["semverve:sync:metadata"].invoke }

        assert_match(/Gemfile\.lock:4:13: locked version 2\.0\.0 -> 2\.0\.1/, stdout)
      end
    end

    def test_sync_metadata_allows_dynamic_gemspec_and_missing_lockfile
      in_project do
        write_module_version("MyGem", "2.0.1")
        write_gemspec("my_gem", dynamic: true)

        Task.new

        assert_equal "Version metadata is in sync.\n", capture_stdout { Rake::Task["semverve:sync:metadata"].invoke }
      end
    end

    def test_sync_metadata_fix_rewrites_literal_gemspec_and_runs_bundle_lock
      commands = []

      in_project do
        gemspec_path = write_gemspec("my_gem", version: "2.0.0")
        write_module_version("MyGem", "2.0.1")
        write_lockfile("my_gem", "2.0.0")

        Task.new do |config|
          config.command_runner = ->(command) { commands << command }
        end

        stdout = capture_stdout { Rake::Task["semverve:sync:metadata:fix"].invoke }

        assert_match(/Updated my_gem\.gemspec/, stdout)
        assert_match(/Replaced 1 metadata version\./, stdout)
        assert_match(/Ran bundle lock\./, stdout)
        assert_match(/spec.version = "2\.0\.1"/, File.read(gemspec_path))
        assert_equal ["bundle lock"], commands
      end
    end

    def test_sync_aggregates_reference_code_and_metadata_findings
      in_project do
        write_gemspec("my_gem", version: "2.0.0")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Install version 2.0.0.\n")
        write_file(File.join("lib", "my_gem", "constants.rb"), "APP_VERSION = \"2.0.0\"\n")

        Task.new do |config|
          config.version_code_reference_files = Rake::FileList["lib/**/*.rb"]
        end

        stdout, _stderr, error = capture_error(Error) { Rake::Task["semverve:sync"].invoke }

        assert_match(/README\.md:1:17: version reference 2\.0\.0 -> 2\.0\.1/, stdout)
        assert_match(%r{lib/my_gem/constants\.rb:1:16: code version literal 2\.0\.0 -> 2\.0\.1}, stdout)
        assert_match(/my_gem\.gemspec:\d+:\d+: gemspec version 2\.0\.0 -> 2\.0\.1/, stdout)
        assert_equal "Found 3 version sync issues.", error.message
      end
    end

    def test_sync_fix_dispatches_all_fixers
      commands = []

      in_project do
        gemspec_path = write_gemspec("my_gem", version: "2.0.0")
        write_module_version("MyGem", "2.0.1")
        readme_path = write_file("README.md", "Install version 2.0.0.\n")
        code_path = write_file(File.join("lib", "my_gem", "constants.rb"), "APP_VERSION = \"2.0.0\"\n")
        write_lockfile("my_gem", "2.0.0")

        Task.new do |config|
          config.command_runner = ->(command) { commands << command }
          config.version_code_reference_files = Rake::FileList["lib/**/*.rb"]
        end

        stdout = capture_stdout { Rake::Task["semverve:sync:fix"].invoke }

        assert_match(/Updated README\.md/, stdout)
        assert_match(%r{Updated lib/my_gem/constants\.rb}, stdout)
        assert_match(/Updated my_gem\.gemspec/, stdout)
        assert_match(/Ran bundle lock\./, stdout)
        assert_equal "Install version 2.0.1.\n", File.read(readme_path)
        assert_match(/APP_VERSION = "2\.0\.1"/, File.read(code_path))
        assert_match(/spec.version = "2\.0\.1"/, File.read(gemspec_path))
        assert_equal ["bundle lock"], commands
      end
    end

    private

    def in_project
      Dir.chdir(@tmpdir) { yield }
    end

    def reset_configuration
      Semverve.instance_variable_set(:@configuration, nil)
    end

    def write_gemspec(name, version: nil, dynamic: false)
      require_line = dynamic ? %(require_relative "lib/#{name}/version"\n) : ""
      version_line = if dynamic
        "  spec.version = #{camelize(name)}::VERSION\n"
      elsif version
        "  spec.version = \"#{version}\"\n"
      else
        ""
      end

      write_file("#{name}.gemspec", <<~RUBY)
        #{require_line}Gem::Specification.new do |spec|
          #{version_line}  spec.name = "#{name}"
        end
      RUBY
    end

    def write_lockfile(name, version)
      write_file("Gemfile.lock", <<~LOCKFILE)
        PATH
          remote: .
          specs:
            #{name} (#{version})

        DEPENDENCIES
          #{name}!

        BUNDLED WITH
           4.0.10
      LOCKFILE
    end

    def camelize(value)
      value.split(/[_-]/).map(&:capitalize).join
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
      stdout, = capture_output { yield }
      stdout
    end

    def capture_output
      original_stdout = $stdout
      original_stderr = $stderr
      output = StringIO.new
      errors = StringIO.new
      $stdout = output
      $stderr = errors
      yield
      [output.string, errors.string]
    ensure
      $stdout = original_stdout
      $stderr = original_stderr
    end

    def capture_error(error_class)
      original_stdout = $stdout
      original_stderr = $stderr
      output = StringIO.new
      errors = StringIO.new
      $stdout = output
      $stderr = errors
      error = assert_raise(error_class) { yield }
      [output.string, errors.string, error]
    ensure
      $stdout = original_stdout
      $stderr = original_stderr
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
