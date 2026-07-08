# frozen_string_literal: true

require "fileutils"
require "json"
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
        assert_not_nil Rake::Task["semverve:check"]
        assert_not_nil Rake::Task["semverve:fix"]
        assert_not_nil Rake::Task["semverve:check:references"]
        assert_not_nil Rake::Task["semverve:fix:references"]
        assert_not_nil Rake::Task["semverve:check:code"]
        assert_not_nil Rake::Task["semverve:fix:code"]
        assert_not_nil Rake::Task["semverve:check:package_metadata"]
        assert_not_nil Rake::Task["semverve:fix:package_metadata"]
        assert_not_nil Rake::Task["semverve:check:rails_config_metadata"]
        assert_not_nil Rake::Task["semverve:fix:rails_config_metadata"]
        assert_not_nil Rake::Task["semverve:check:rubygems"]
        assert_not_nil Rake::Task["semverve:check:release"]
        assert_raise(RuntimeError) { Rake::Task["version:current"] }
      end
    end

    def test_task_file_does_not_install_tasks_until_task_is_initialized
      assert_raise(RuntimeError) { Rake::Task["semverve:current"] }
    end

    def test_defines_tasks_under_configured_namespace
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")

        Task.new { |config| config.task_namespace = :version }

        assert_not_nil Rake::Task["version:current"]
        assert_not_nil Rake::Task["version:set"]
        assert_not_nil Rake::Task["version:increment:patch"]
        assert_not_nil Rake::Task["version:check:references"]
        assert_not_nil Rake::Task["version:fix:references"]
        assert_not_nil Rake::Task["version:check:release"]
        assert_raise(RuntimeError) { Rake::Task["semverve:current"] }
        assert_equal "2.0.1\n", capture_stdout { Rake::Task["version:current"].invoke }
      end
    end

    def test_configured_namespace_is_used_in_task_help_messages
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")

        Task.new { |config| config.task_namespace = "version" }

        set_error = assert_raise(Error) { Rake::Task["version:set"].invoke }
        assert_equal "Run rake 'version:set[MAJOR.MINOR.PATCH]'.", set_error.message

        check_error = assert_raise(Error) { Rake::Task["version:check"].invoke("nope") }
        assert_equal "Run rake 'version:check[MAJOR.MINOR.PATCH]'.", check_error.message

        generate_error = assert_raise(Error) { Rake::Task["version:generate"].invoke }
        assert_match(/version:generate\[force\]/, generate_error.message)
      end
    end

    def test_configured_namespace_is_used_in_missing_version_file_help
      in_project do
        write_gemspec("my_gem")

        Task.new { |config| config.task_namespace = :version }

        error = assert_raise(Error) { Rake::Task["version:current"].invoke }
        assert_match(/Run rake version:generate/, error.message)
      end
    end

    def test_version_check_registry_resolves_core_and_adapter_checks
      core_check = VersionChecks.fetch(:doc_references, extra_checks: Adapters.checks)
      rails_check = VersionChecks.fetch(:rails_config_metadata, extra_checks: Adapters.checks)

      assert_equal :doc_references, core_check.name
      assert_equal :rails_config_metadata, rails_check.name
    end

    def test_adapter_registry_exposes_framework_checks
      rails_checks = Adapters.fetch(:rails).checks.map(&:name)
      sinatra_checks = Adapters.fetch(:sinatra).checks.map(&:name)

      assert_equal [:rails_config_metadata], rails_checks
      assert_empty sinatra_checks
    end

    def test_finding_is_public_check_result_data
      version = SemanticVersion.parse("1.2.3")
      finding = Finding.new(path: "README.md", line: 2, column: 10, version: version)
      labeled = Finding.new(path: "Gemfile.lock", line: 4, column: 13, version: version, label: "locked version")

      assert_equal "README.md", finding.path
      assert_equal 2, finding.line
      assert_equal 10, finding.column
      assert_equal version, finding.version
      assert_nil finding.label
      assert_equal "locked version", labeled.label
    end

    def test_fix_result_is_public_check_result_data
      default_result = FixResult.new(changed_files: ["README.md"], replacement_count: 1)
      bundle_result = FixResult.new(changed_files: [], replacement_count: 0, bundle_lock_ran: true)

      assert_equal ["README.md"], default_result.changed_files
      assert_equal 1, default_result.replacement_count
      refute default_result.bundle_lock_ran
      assert bundle_result.bundle_lock_ran
    end

    def test_version_match_policy_matches_older_non_current_and_exact_targets
      current_version = SemanticVersion.parse("2.0.1")
      older_version = SemanticVersion.parse("2.0.0")
      newer_version = SemanticVersion.parse("2.0.2")

      older_policy = VersionMatchPolicy.new(current_version: current_version, match_mode: :older)
      non_current_policy = VersionMatchPolicy.new(current_version: current_version, match_mode: :non_current)
      exact_policy = VersionMatchPolicy.new(
        current_version: current_version,
        match_mode: :older,
        target_version: newer_version
      )

      assert older_policy.report?(older_version)
      refute older_policy.report?(newer_version)
      assert non_current_policy.report?(older_version)
      assert non_current_policy.report?(newer_version)
      refute non_current_policy.report?(current_version)
      assert exact_policy.report?(newer_version)
      refute exact_policy.report?(older_version)
    end

    def test_version_match_policy_rejects_unknown_modes
      policy = VersionMatchPolicy.new(current_version: SemanticVersion.parse("2.0.1"), match_mode: :everything)

      error = assert_raise(Error) { policy.report?(SemanticVersion.parse("2.0.0")) }

      assert_equal "Unknown version match mode :everything. Use :older or :non_current.", error.message
    end

    def test_version_literal_rewriter_replaces_only_named_capture
      rewriter = VersionLiteralRewriter.new(
        pattern: /release\s+(?<quote>["'])(?<version>\d+\.\d+\.\d+)\k<quote>/,
        replacement: "2.0.1"
      )

      assert_equal %(release "2.0.1"), rewriter.rewrite(%(release "2.0.0"))
    end

    def test_version_literal_rewriter_requires_named_capture
      error = assert_raise(Error) do
        VersionLiteralRewriter.new(pattern: /release\s+(\d+\.\d+\.\d+)/, replacement: "2.0.1")
      end

      assert_equal "version literal pattern must include a named capture called version.", error.message
    end

    def test_check_objects_accept_injected_scanners
      scanner = Class.new do
        class << self
          attr_accessor :initialized_with
        end

        def initialize(configuration, current_version, include_ignored: false, target_version: nil)
          self.class.initialized_with = [configuration, current_version, include_ignored, target_version]
        end

        def findings
          [Finding.new(path: "README.md", line: 1, column: 1, version: SemanticVersion.parse("2.0.0"))]
        end

        def fix
          FixResult.new(changed_files: ["README.md"], replacement_count: 1)
        end
      end
      configuration = Object.new
      current_version = SemanticVersion.parse("2.0.1")
      target_version = SemanticVersion.parse("2.0.0")
      check = VersionChecks::DocReferences.new(scanner: scanner)

      findings = check.findings(configuration, current_version, include_ignored: true, target_version: target_version)
      assert_equal [configuration, current_version, true, target_version], scanner.initialized_with

      result = check.fix(configuration, current_version, target_version: target_version)

      assert_instance_of Finding, findings.first
      assert_instance_of FixResult, result
      assert_equal [configuration, current_version, false, target_version], scanner.initialized_with
    end

    def test_check_surfaces_return_public_finding_and_fix_result_objects
      in_project do
        write_gemspec("my_gem", version: "2.0.0")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Install version 2.0.0.\n")
        write_file(File.join("lib", "my_gem", "constants.rb"), "APP_VERSION = \"2.0.0\"\n")
        write_file("config/application.rb", "config.x.version = \"2.0.0\"\n")

        Semverve.configure do |config|
          config.version_code_reference_files = Rake::FileList["lib/**/*.rb"]
        end

        configuration = Semverve.configuration.resolved
        current_version = SemanticVersion.parse("2.0.1")
        checks = [
          VersionReferences.new(configuration, current_version),
          VersionCodeReferences.new(configuration, current_version),
          RailsConfigMetadata.new(configuration, current_version),
          PackageMetadata.new(configuration, current_version)
        ]

        checks.each do |check|
          assert_instance_of Finding, check.findings.first
          assert_instance_of FixResult, check.fix
        end
      end
    end

    def test_exact_target_fix_note_uses_check_api_not_labels
      current_version = SemanticVersion.parse("2.0.1")
      check = Class.new do
        def exact_target_fix_noop_notice?
          true
        end
      end.new
      finding = Finding.new(path: "README.md", line: 1, column: 1, version: current_version)
      result = VersionAudit::CheckResult.new(
        current_version: current_version,
        target_version: current_version,
        groups: [
          VersionAudit::FindingGroup.new(
            check: check,
            label: "custom label",
            findings: [finding]
          )
        ],
        clean_message: "clean"
      )

      stdout, _stderr, error = capture_error(Error) do
        TaskReporter.new.report_check(result, fix_task_name: "semverve:fix")
      end

      assert_match(/README\.md:1:1: custom label 2\.0\.1 -> 2\.0\.1/, stdout)
      assert_match(/semverve:fix\[2\.0\.1\] will not change these references/, stdout)
      assert_equal "Found 1 version check issue.", error.message
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

        stdout = capture_stdout { Rake::Task["semverve:set"].invoke("2.3.4") }

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

        stdout = capture_stdout { Rake::Task["semverve:set"].invoke("2.3.4") }

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
        assert_equal "Run rake 'semverve:set[MAJOR.MINOR.PATCH]'.", error.message
      end
    end

    def test_set_ignores_env_version
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")

        Task.new

        error = with_env("SEMVERVE_VERSION" => "2.3.4") do
          assert_raise(Error) { Rake::Task["semverve:set"].invoke }
        end

        assert_equal "Run rake 'semverve:set[MAJOR.MINOR.PATCH]'.", error.message
      end
    end

    def test_set_fails_with_invalid_version
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")

        Task.new

        error = assert_raise(Error) { Rake::Task["semverve:set"].invoke("nope") }

        assert_match(/Expected a semantic version/, error.message)
      end
    end

    def test_check_target_fails_with_invalid_version
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")

        Task.new

        error = assert_raise(Error) { Rake::Task["semverve:check"].invoke("nope") }

        assert_equal "Run rake 'semverve:check[MAJOR.MINOR.PATCH]'.", error.message
      end
    end

    def test_set_lower_version_warns_and_updates
      in_project do
        write_gemspec("my_gem")
        path = write_module_version("MyGem", "2.0.1")

        Task.new

        stdout, stderr = capture_output { Rake::Task["semverve:set"].invoke("1.9.9") }

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

        stdout, stderr = capture_output { Rake::Task["semverve:set"].invoke("2.0.1") }

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

        capture_stdout { Rake::Task["semverve:set"].invoke("2.0.2") }

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

    def test_configure_before_task_initialization_sets_task_configuration
      in_project do
        write_gemspec("ignored_name")
        custom_path = File.join("custom", "version.rb")
        write_simple_version("CustomGem", "1.2.3", path: custom_path)

        Semverve.configure do |config|
          config.task_namespace = :version
          config.gem_name = "custom_gem"
          config.module_name = "CustomGem"
          config.version_file = custom_path
          config.format = :simple
        end

        Task.new

        assert_not_nil Rake::Task["version:current"]
        assert_raise(RuntimeError) { Rake::Task["semverve:current"] }
        assert_equal "1.2.3\n", capture_stdout { Rake::Task["version:current"].invoke }
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

    def test_rails_preset_resolves_rails_defaults
      in_project do
        with_stubbed_rails(root: @tmpdir, application: rails_application("Storefront")) do
          Semverve.configure do |config|
            config.preset = :rails
          end

          resolved = Semverve.configuration.resolved

          assert_equal :simple, resolved.format
          assert_equal "Storefront", resolved.module_name
          assert_nil resolved.gem_name
          assert_equal File.expand_path(@tmpdir), resolved.root
          assert_equal [:doc_references, :code_references, :rails_config_metadata], resolved.version_checks
          assert_equal File.join("config", "version.rb"), resolved.version_file
        end
      end
    end

    def test_rails_adapter_resolves_the_same_defaults_as_preset
      in_project do
        with_stubbed_rails(root: @tmpdir, application: rails_application("Storefront")) do
          Semverve.configure do |config|
            config.adapter = :rails
          end

          adapter_resolved = Semverve.configuration.resolved
          reset_configuration

          Semverve.configure do |config|
            config.preset = :rails
          end

          preset_resolved = Semverve.configuration.resolved

          assert_equal preset_resolved.format, adapter_resolved.format
          assert_equal preset_resolved.module_name, adapter_resolved.module_name
          assert_equal preset_resolved.gem_name, adapter_resolved.gem_name
          assert_equal preset_resolved.root, adapter_resolved.root
          assert_equal preset_resolved.version_checks, adapter_resolved.version_checks
          assert_equal preset_resolved.version_file, adapter_resolved.version_file
        end
      end
    end

    def test_rails_preset_falls_back_to_project_directory_for_module_name
      root = File.join(@tmpdir, "my-rails-app")

      with_stubbed_rails(root: root, application: Class.new.new) do
        Semverve.configure do |config|
          config.preset = :rails
        end

        assert_equal "MyRailsApp", Semverve.configuration.resolved.module_name
      end
    end

    def test_rails_preset_respects_explicit_overrides
      in_project do
        custom_root = File.join(@tmpdir, "custom-root")

        with_stubbed_rails(root: @tmpdir, application: rails_application("Storefront")) do
          Semverve.configure do |config|
            config.preset = :rails
            config.format = :module
            config.module_name = "CustomApp"
            config.root = custom_root
            config.version_checks = [:package_metadata]
            config.version_file = File.join("config", "releases", "version.rb")
          end

          resolved = Semverve.configuration.resolved

          assert_equal :module, resolved.format
          assert_equal "CustomApp", resolved.module_name
          assert_equal File.expand_path(custom_root), resolved.root
          assert_equal [:package_metadata], resolved.version_checks
          assert_equal File.join("config", "releases", "version.rb"), resolved.version_file
        end
      end
    end

    def test_unknown_adapter_fails_loudly
      error = assert_raises(Error) do
        Semverve.configure do |config|
          config.adapter = :hanami
        end
      end

      assert_equal "Unknown adapter :hanami. Use :rails, or :sinatra.", error.message
    end

    def test_unknown_preset_uses_adapter_validation
      error = assert_raises(Error) do
        Semverve.configure do |config|
          config.preset = :hanami
        end
      end

      assert_equal "Unknown adapter :hanami. Use :rails, or :sinatra.", error.message
    end

    def test_sinatra_adapter_resolves_defaults_without_gemspec
      in_project do
        write_simple_version("SemverveTest", "2.0.1", path: File.join("config", "version.rb"))

        Task.new do |config|
          config.adapter = :sinatra
        end

        resolved = Semverve.configuration.resolved

        assert_equal :simple, resolved.format
        assert_equal camelize(File.basename(File.expand_path(Dir.pwd))), resolved.module_name
        assert_nil resolved.gem_name
        assert_equal File.expand_path(Dir.pwd), resolved.root
        assert_equal [:doc_references, :code_references], resolved.version_checks
        assert_equal File.join("config", "version.rb"), resolved.version_file
        assert_equal "2.0.1\n", capture_stdout { Rake::Task["semverve:current"].invoke }
      end
    end

    def test_sinatra_adapter_does_not_infer_config_as_gem_name
      in_project do
        write_simple_version("SemverveTest", "2.0.1", path: File.join("config", "version.rb"))
        write_lockfile("config", "1.0.0")

        Task.new do |config|
          config.adapter = :sinatra
        end

        assert_nil Semverve.configuration.resolved.gem_name
        assert_equal "Package metadata is current.\n",
          capture_stdout { Rake::Task["semverve:check:package_metadata"].invoke }
      end
    end

    def test_current_reads_rails_preset_without_gemspec
      in_project do
        write_simple_version("Storefront", "2.0.1", path: File.join("config", "version.rb"))

        with_stubbed_rails(root: @tmpdir, application: rails_application("Storefront")) do
          Task.new do |config|
            config.preset = :rails
          end

          assert_equal "2.0.1\n", capture_stdout { Rake::Task["semverve:current"].invoke }
        end
      end
    end

    def test_rails_package_metadata_does_not_infer_config_as_gem_name
      in_project do
        write_simple_version("Storefront", "2.0.1", path: File.join("config", "version.rb"))
        write_lockfile("config", "1.0.0")

        with_stubbed_rails(root: @tmpdir, application: rails_application("Storefront")) do
          Task.new do |config|
            config.preset = :rails
          end

          assert_nil Semverve.configuration.resolved.gem_name
          assert_equal "Package metadata is current.\n",
            capture_stdout { Rake::Task["semverve:check:package_metadata"].invoke }
        end
      end
    end

    def test_railtie_sets_rails_preset_and_installs_tasks
      in_project do
        with_stubbed_rails(root: @tmpdir, application: rails_application("Storefront")) do
          require_relative "../../lib/semverve/railtie"

          Semverve::Railtie.rake_tasks_blocks.each(&:call)

          assert_equal :rails, Semverve.configuration.preset
          assert_not_nil Rake::Task["semverve:current"]
        end
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

    def test_generate_infers_gem_name_from_dynamic_gemspec_with_missing_version_file
      in_project do
        write_gemspec("my_gem", dynamic: true)

        Task.new

        output = capture_stdout { Rake::Task["semverve:generate"].invoke }
        path = File.realpath(File.join(@tmpdir, "lib", "my_gem", "version.rb"))

        assert_match(/Generated #{Regexp.escape(path)}/, output)
        assert_match(/module MyGem/, File.read(path))
      end
    end

    def test_generate_can_bootstrap_when_rakefile_guards_bundler_gem_tasks
      in_project do
        write_gemspec("docstor", dynamic: true)
        write_file("Rakefile", <<~RUBY)
          require "semverve/task"

          unless ARGV.any? { |arg| arg.start_with?("semverve:generate") }
            require "bundler/gem_tasks"
          end

          Semverve::Task.new
        RUBY

        with_argv(["semverve:generate"]) do
          load File.join(@tmpdir, "Rakefile")
          output = capture_stdout { Rake::Task["semverve:generate"].invoke }
          path = File.realpath(File.join(@tmpdir, "lib", "docstor", "version.rb"))

          assert_match(/Generated #{Regexp.escape(path)}/, output)
          assert_match(/module Docstor/, File.read(path))
        end
      end
    end

    def test_generate_accepts_version_and_format_arguments
      in_project do
        write_gemspec("my_gem")

        Task.new

        capture_stdout { Rake::Task["semverve:generate"].invoke("1.2.3", "simple") }

        assert_match(/VERSION = "1.2.3"/, File.read(File.join(@tmpdir, "lib", "my_gem", "version.rb")))
      end
    end

    def test_generate_accepts_format_without_version
      in_project do
        write_gemspec("my_gem")

        Task.new

        capture_stdout { Rake::Task["semverve:generate"].invoke("simple") }

        assert_match(/VERSION = "0.1.0"/, File.read(File.join(@tmpdir, "lib", "my_gem", "version.rb")))
      end
    end

    def test_generate_accepts_arguments_in_any_order
      in_project do
        write_gemspec("my_gem")

        Task.new

        capture_stdout { Rake::Task["semverve:generate"].invoke("simple", "1.2.3") }

        assert_match(/VERSION = "1.2.3"/, File.read(File.join(@tmpdir, "lib", "my_gem", "version.rb")))
      end
    end

    def test_generate_ignores_env_version_and_format
      in_project do
        write_gemspec("my_gem")

        Task.new

        with_env("SEMVERVE_VERSION" => "1.2.3", "SEMVERVE_FORMAT" => "simple") do
          capture_stdout { Rake::Task["semverve:generate"].invoke }
        end

        content = File.read(File.join(@tmpdir, "lib", "my_gem", "version.rb"))
        assert_match(/module MyGem/, content)
        assert_match(/MAJOR = 0/, content)
        assert_match(/MINOR = 1/, content)
        assert_match(/PATCH = 0/, content)
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

        capture_stdout { Rake::Task["semverve:generate"].invoke("1.2.3", "simple", "force") }

        assert_match(/VERSION = "1\.2\.3"/, File.read(path))
      end
    end

    def test_generate_accepts_force_token_after_format
      in_project do
        write_gemspec("my_gem")
        path = write_module_version("MyGem", "2.0.1")

        Task.new

        capture_stdout { Rake::Task["semverve:generate"].invoke("simple", "force") }

        assert_match(/VERSION = "0\.1\.0"/, File.read(path))
      end
    end

    def test_generate_accepts_force_token_without_version_or_format
      in_project do
        write_gemspec("my_gem")
        path = write_module_version("MyGem", "2.0.1")

        Task.new

        capture_stdout { Rake::Task["semverve:generate"].invoke("force") }

        assert_match(/MAJOR = 0/, File.read(path))
        assert_match(/MINOR = 1/, File.read(path))
        assert_match(/PATCH = 0/, File.read(path))
      end
    end

    def test_generate_accepts_force_token_after_version
      in_project do
        write_gemspec("my_gem")
        path = write_module_version("MyGem", "2.0.1")

        Task.new

        capture_stdout { Rake::Task["semverve:generate"].invoke("1.2.3", "force") }

        assert_match(/MAJOR = 1/, File.read(path))
        assert_match(/MINOR = 2/, File.read(path))
        assert_match(/PATCH = 3/, File.read(path))
      end
    end

    def test_generate_ignores_env_force
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")

        Task.new

        error = with_env("SEMVERVE_FORCE" => "true") do
          assert_raise(Error) { Rake::Task["semverve:generate"].invoke }
        end

        assert_match(/semverve:generate\[force\]/, error.message)
      end
    end

    def test_generate_rejects_boolean_force_argument
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")

        Task.new

        error = assert_raise(Error) { Rake::Task["semverve:generate"].invoke("1.2.3", "simple", "true") }

        assert_equal "Unknown generate option \"true\". Use a semantic version, module, simple, or force.", error.message
      end
    end

    def test_generate_rejects_unknown_arguments
      in_project do
        write_gemspec("my_gem")

        Task.new

        error = assert_raise(Error) { Rake::Task["semverve:generate"].invoke("1.2.3", "simple", "later") }

        assert_equal "Unknown generate option \"later\". Use a semantic version, module, simple, or force.", error.message
      end
    end

    def test_generate_rejects_duplicate_versions
      in_project do
        write_gemspec("my_gem")

        Task.new

        error = assert_raise(Error) { Rake::Task["semverve:generate"].invoke("1.2.3", "2.3.4") }

        assert_equal "Duplicate generate version \"2.3.4\".", error.message
      end
    end

    def test_generate_rejects_duplicate_formats
      in_project do
        write_gemspec("my_gem")

        Task.new

        error = assert_raise(Error) { Rake::Task["semverve:generate"].invoke("simple", "module") }

        assert_equal "Duplicate generate format \"module\".", error.message
      end
    end

    def test_generate_rejects_duplicate_force
      in_project do
        write_gemspec("my_gem")

        Task.new

        error = assert_raise(Error) { Rake::Task["semverve:generate"].invoke("force", "force") }

        assert_equal "Duplicate generate option force.", error.message
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

    def test_gemspec_without_literal_name_fails_without_override
      in_project do
        write_file("my_gem.gemspec", <<~RUBY)
          Gem::Specification.new do |spec|
            spec.summary = "No name here"
          end
        RUBY

        Task.new

        error = assert_raise(Error) { Rake::Task["semverve:current"].invoke }
        assert_match(/Could not infer gem name/, error.message)
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

    def test_check_scans_readme_files_by_default
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Install version 2.0.0.\n")
        write_file(File.join("guides", "README.md"), "Upgrade from 1.9.9.\n")
        write_file(File.join("doc", "usage.md"), "Generated docs mention 1.0.0.\n")

        Task.new

        stdout, stderr, error = capture_error(Error) { Rake::Task["semverve:check:references"].invoke }

        assert_match(/README\.md:1:17: version reference 2\.0\.0 -> 2\.0\.1/, stdout)
        assert_match(%r{guides/README\.md:1:14: version reference 1\.9\.9 -> 2\.0\.1}, stdout)
        assert_no_match(/doc\/usage\.md/, stdout)
        assert_equal "Found 2 version check issues.", error.message
        assert_empty stderr
      end
    end

    def test_check_can_append_to_default_doc_reference_files
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Install version 2.0.0.\n")
        write_file(File.join("doc", "usage.md"), "Documented as 1.0.0.\n")

        Task.new do |config|
          config.version_doc_reference_files.append("doc/**/*.md")
        end

        stdout, = capture_error(Error) { Rake::Task["semverve:check:references"].invoke }

        assert_match(/README\.md:1:17: version reference 2\.0\.0 -> 2\.0\.1/, stdout)
        assert_match(%r{doc/usage\.md:1:15: version reference 1\.0\.0 -> 2\.0\.1}, stdout)
      end
    end

    def test_check_can_replace_default_doc_reference_files
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Install version 2.0.0.\n")
        write_file(File.join("guides", "usage.md"), "Documented as 1.0.0.\n")

        Task.new do |config|
          config.version_doc_reference_files = Rake::FileList["guides/**/*.md"]
        end

        stdout, = capture_error(Error) { Rake::Task["semverve:check:references"].invoke }

        assert_no_match(/README\.md/, stdout)
        assert_match(%r{guides/usage\.md:1:15: version reference 1\.0\.0 -> 2\.0\.1}, stdout)
      end
    end

    def test_check_defaults_to_older_version_references
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Old 2.0.0, current 2.0.1, future 2.0.2.\n")

        Task.new

        stdout, = capture_error(Error) { Rake::Task["semverve:check:references"].invoke }

        assert_match(/README\.md:1:5: version reference 2\.0\.0 -> 2\.0\.1/, stdout)
        assert_no_match(/2\.0\.2 -> 2\.0\.1/, stdout)
      end
    end

    def test_check_can_report_non_current_version_references
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Old 2.0.0, current 2.0.1, future 2.0.2.\n")

        Task.new do |config|
          config.version_match_mode = :non_current
        end

        stdout, = capture_error(Error) { Rake::Task["semverve:check:references"].invoke }

        assert_match(/README\.md:1:5: version reference 2\.0\.0 -> 2\.0\.1/, stdout)
        assert_match(/README\.md:1:34: version reference 2\.0\.2 -> 2\.0\.1/, stdout)
        assert_no_match(/current 2\.0\.1 -> 2\.0\.1/, stdout)
      end
    end

    def test_check_can_target_exact_version_references
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Old 2.0.0, current 2.0.1, future 2.0.2.\n")

        Task.new

        stdout, = capture_error(Error) { Rake::Task["semverve:check:references"].invoke("2.0.2") }

        assert_no_match(/2\.0\.0 -> 2\.0\.1/, stdout)
        assert_match(/README\.md:1:34: version reference 2\.0\.2 -> 2\.0\.1/, stdout)
        assert_no_match(/current 2\.0\.1 -> 2\.0\.1/, stdout)
      end
    end

    def test_check_target_version_overrides_non_current_mode
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Old 2.0.0, current 2.0.1, future 2.0.2.\n")

        Task.new do |config|
          config.version_match_mode = :non_current
        end

        stdout, = capture_error(Error) { Rake::Task["semverve:check:references"].invoke("2.0.0") }

        assert_match(/README\.md:1:5: version reference 2\.0\.0 -> 2\.0\.1/, stdout)
        assert_no_match(/2\.0\.2 -> 2\.0\.1/, stdout)
      end
    end

    def test_check_scans_ruby_comments_without_scanning_code_literals
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

        stdout, = capture_error(Error) { Rake::Task["semverve:check:references"].invoke }

        assert_no_match(/1:20/, stdout)
        assert_match(%r{lib/my_gem/example\.rb:2:15: version reference 1\.0\.0 -> 2\.0\.1}, stdout)
      end
    end

    def test_check_fix_replaces_version_references
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

        stdout = capture_stdout { Rake::Task["semverve:fix:references"].invoke }

        assert_match(/Updated README\.md/, stdout)
        assert_match(%r{Updated lib/my_gem/example\.rb}, stdout)
        assert_match(/Replaced 2 version references\./, stdout)
        assert_equal "Install version 2.0.1.\n", File.read(readme_path)
        assert_match(/EXAMPLE_VERSION = "1\.0\.0"/, File.read(example_path))
        assert_match(/# See version 2\.0\.1\./, File.read(example_path))
      end
    end

    def test_check_fix_replaces_only_targeted_version_references
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        readme_path = write_file("README.md", "Old 1.9.9, target 2.0.0, future 2.0.2.\n")

        Task.new

        stdout = capture_stdout { Rake::Task["semverve:fix:references"].invoke("2.0.0") }

        assert_match(/Updated README\.md/, stdout)
        assert_match(/Replaced 1 version reference\./, stdout)
        assert_equal "Old 1.9.9, target 2.0.1, future 2.0.2.\n", File.read(readme_path)
      end
    end

    def test_check_fix_reports_clean_doc_reference_files
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Install version 2.0.1.\n")

        Task.new

        assert_equal "Version references are current.\n", capture_stdout { Rake::Task["semverve:fix:references"].invoke }
      end
    end

    def test_check_current_target_reports_references_with_no_fix_note
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Install version 2.0.1.\n")

        Task.new

        stdout, _stderr, error = capture_error(Error) { Rake::Task["semverve:check:references"].invoke("2.0.1") }

        assert_match(/README\.md:1:17: version reference 2\.0\.1 -> 2\.0\.1/, stdout)
        assert_match(
          /Target version 2\.0\.1 is already current; semverve:fix:references\[2\.0\.1\] will not change these references\./,
          stdout
        )
        assert_equal "Found 1 version check issue.", error.message
      end
    end

    def test_fix_current_target_is_noop
      commands = []

      in_project do
        gemspec_path = write_gemspec("my_gem", version: "2.0.0")
        write_module_version("MyGem", "2.0.1")
        readme_path = write_file("README.md", "Install version 2.0.1.\n")
        write_lockfile("my_gem", "2.0.0")

        Task.new do |config|
          config.command_runner = ->(command) { commands << command }
        end

        stdout = capture_stdout { Rake::Task["semverve:fix"].invoke("2.0.1") }

        assert_equal "Target version 2.0.1 is already current; nothing to fix.\n", stdout
        assert_equal "Install version 2.0.1.\n", File.read(readme_path)
        assert_match(/spec.version = "2\.0\.0"/, File.read(gemspec_path))
        assert_empty commands
      end
    end

    def test_check_honors_inline_ignore_markers
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

        stdout, = capture_error(Error) { Rake::Task["semverve:check:references"].invoke }

        assert_no_match(/1\.0\.0/, stdout)
        assert_no_match(/1\.5\.0/, stdout)
        assert_match(/README\.md:5:13: version reference 1\.9\.9 -> 2\.0\.1/, stdout)
      end
    end

    def test_check_reports_ignored_reference_findings_when_requested
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", <<~MARKDOWN)
          Same line 1.0.0. <!-- semverve:ignore-version-reference -->
          <!-- semverve:ignore-version-reference -->

          Previous marker ignores 1.5.0.
        MARKDOWN

        Task.new

        stdout, _stderr, error = with_env("SEMVERVE_REPORT_IGNORED" => "true") do
          capture_error(Error) { Rake::Task["semverve:check:references"].invoke }
        end

        assert_match(/README\.md:1:11: version reference 1\.0\.0 -> 2\.0\.1/, stdout)
        assert_match(/README\.md:4:25: version reference 1\.5\.0 -> 2\.0\.1/, stdout)
        assert_equal "Found 2 version check issues.", error.message
      end
    end

    def test_check_reports_clean_doc_reference_files
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Install version 2.0.1.\n")

        Task.new

        assert_equal "Version references are current.\n", capture_stdout { Rake::Task["semverve:check:references"].invoke }
      end
    end

    def test_check_ignores_configured_non_scannable_doc_files
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file("metadata.json", "{\"version\":\"1.0.0\"}\n")

        Task.new do |config|
          config.version_doc_reference_files = Rake::FileList["metadata.json"]
        end

        assert_equal "Version references are current.\n", capture_stdout { Rake::Task["semverve:check:references"].invoke }
      end
    end

    def test_check_code_reports_safe_version_literals
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file(File.join("lib", "my_gem", "constants.rb"), <<~RUBY)
          APP_VERSION = "2.0.0"
          FUTURE_VERSION = "2.0.2"
          EXAMPLE = "1.0.0"
        RUBY

        Task.new do |config|
          config.version_code_reference_files = Rake::FileList["lib/**/*.rb"]
        end

        stdout, = capture_error(Error) { Rake::Task["semverve:check:code"].invoke }

        assert_match(%r{lib/my_gem/constants\.rb:1:16: code version literal 2\.0\.0 -> 2\.0\.1}, stdout)
        assert_no_match(/2\.0\.2 -> 2\.0\.1/, stdout)
        assert_no_match(/1\.0\.0/, stdout)
      end
    end

    def test_check_code_can_report_non_current_version_literals
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file(File.join("lib", "my_gem", "constants.rb"), <<~RUBY)
          APP_VERSION = "2.0.0"
          CURRENT_VERSION = "2.0.1"
          FUTURE_VERSION = "2.0.2"
        RUBY

        Task.new do |config|
          config.version_match_mode = :non_current
          config.version_code_reference_files = Rake::FileList["lib/**/*.rb"]
        end

        stdout, = capture_error(Error) { Rake::Task["semverve:check:code"].invoke }

        assert_match(%r{lib/my_gem/constants\.rb:1:16: code version literal 2\.0\.0 -> 2\.0\.1}, stdout)
        assert_match(%r{lib/my_gem/constants\.rb:3:19: code version literal 2\.0\.2 -> 2\.0\.1}, stdout)
        assert_no_match(/CURRENT_VERSION/, stdout)
      end
    end

    def test_check_code_can_target_exact_version_literals
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file(File.join("lib", "my_gem", "constants.rb"), <<~RUBY)
          APP_VERSION = "2.0.0"
          FUTURE_VERSION = "2.0.2"
        RUBY

        Task.new do |config|
          config.version_code_reference_files = Rake::FileList["lib/**/*.rb"]
        end

        stdout, = capture_error(Error) { Rake::Task["semverve:check:code"].invoke("2.0.2") }

        assert_no_match(/2\.0\.0 -> 2\.0\.1/, stdout)
        assert_match(%r{lib/my_gem/constants\.rb:2:19: code version literal 2\.0\.2 -> 2\.0\.1}, stdout)
      end
    end

    def test_check_code_fix_replaces_safe_version_literals
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

        stdout = capture_stdout { Rake::Task["semverve:fix:code"].invoke }

        assert_match(%r{Updated lib/my_gem/constants\.rb}, stdout)
        assert_match(/Replaced 1 code version literal\./, stdout)
        assert_match(/APP_VERSION = "2\.0\.1"/, File.read(path))
        assert_match(/EXAMPLE = "1\.0\.0"/, File.read(path))
      end
    end

    def test_check_code_fix_replaces_only_targeted_version_literals
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        path = write_file(File.join("lib", "my_gem", "constants.rb"), <<~RUBY)
          OLD_VERSION = "1.9.9"
          APP_VERSION = "2.0.0"
          FUTURE_VERSION = "2.0.2"
        RUBY

        Task.new do |config|
          config.version_code_reference_files = Rake::FileList["lib/**/*.rb"]
        end

        stdout = capture_stdout { Rake::Task["semverve:fix:code"].invoke("2.0.0") }
        content = File.read(path)

        assert_match(%r{Updated lib/my_gem/constants\.rb}, stdout)
        assert_match(/Replaced 1 code version literal\./, stdout)
        assert_match(/OLD_VERSION = "1\.9\.9"/, content)
        assert_match(/APP_VERSION = "2\.0\.1"/, content)
        assert_match(/FUTURE_VERSION = "2\.0\.2"/, content)
      end
    end

    def test_check_code_honors_inline_ignore_markers
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file(File.join("lib", "my_gem", "constants.rb"), <<~RUBY)
          IGNORED_VERSION = "2.0.0" # semverve:ignore-version-reference
          # semverve:ignore-version-reference
          PREVIOUS_IGNORED_VERSION = "2.0.0"
          APP_VERSION = "2.0.0"
        RUBY

        Task.new do |config|
          config.version_code_reference_files = Rake::FileList["lib/**/*.rb"]
        end

        stdout, = capture_error(Error) { Rake::Task["semverve:check:code"].invoke }

        assert_no_match(%r{lib/my_gem/constants\.rb:1:20: code version literal 2\.0\.0 -> 2\.0\.1}, stdout)
        assert_no_match(%r{lib/my_gem/constants\.rb:3:29: code version literal 2\.0\.0 -> 2\.0\.1}, stdout)
        assert_match(%r{lib/my_gem/constants\.rb:4:16: code version literal 2\.0\.0 -> 2\.0\.1}, stdout)
      end
    end

    def test_check_code_reports_ignored_findings_when_requested
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file(File.join("lib", "my_gem", "constants.rb"), <<~RUBY)
          IGNORED_VERSION = "2.0.0" # semverve:ignore-version-reference
          # semverve:ignore-version-reference
          PREVIOUS_IGNORED_VERSION = "2.0.0"
        RUBY

        Task.new do |config|
          config.version_code_reference_files = Rake::FileList["lib/**/*.rb"]
        end

        stdout, _stderr, error = with_env("SEMVERVE_REPORT_IGNORED" => "true") do
          capture_error(Error) { Rake::Task["semverve:check:code"].invoke }
        end

        assert_match(%r{lib/my_gem/constants\.rb:1:20: code version literal 2\.0\.0 -> 2\.0\.1}, stdout)
        assert_match(%r{lib/my_gem/constants\.rb:3:29: code version literal 2\.0\.0 -> 2\.0\.1}, stdout)
        assert_equal "Found 2 version check issues.", error.message
      end
    end

    def test_check_code_fix_honors_inline_ignore_markers
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        path = write_file(File.join("lib", "my_gem", "constants.rb"), <<~RUBY)
          IGNORED_VERSION = "2.0.0" # semverve:ignore-version-reference
          # semverve:ignore-version-reference
          PREVIOUS_IGNORED_VERSION = "2.0.0"
          APP_VERSION = "2.0.0"
        RUBY

        Task.new do |config|
          config.version_code_reference_files = Rake::FileList["lib/**/*.rb"]
        end

        stdout = capture_stdout { Rake::Task["semverve:fix:code"].invoke }
        content = File.read(path)

        assert_match(%r{Updated lib/my_gem/constants\.rb}, stdout)
        assert_match(/Replaced 1 code version literal\./, stdout)
        assert_match(/IGNORED_VERSION = "2\.0\.0"/, content)
        assert_match(/PREVIOUS_IGNORED_VERSION = "2\.0\.0"/, content)
        assert_match(/APP_VERSION = "2\.0\.1"/, content)
      end
    end

    def test_check_code_accepts_custom_version_literal_pattern
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        write_file(File.join("lib", "my_gem", "constants.rb"), <<~RUBY)
          release "2.0.0"
          EXAMPLE = "1.0.0"
        RUBY

        Task.new do |config|
          config.version_code_reference_files = Rake::FileList["lib/**/*.rb"]
          config.version_code_reference_pattern = /release ["'](?<version>\d+\.\d+\.\d+)["']/
        end

        stdout, = capture_error(Error) { Rake::Task["semverve:check:code"].invoke }

        assert_match(%r{lib/my_gem/constants\.rb:1:10: code version literal 2\.0\.0 -> 2\.0\.1}, stdout)
        assert_no_match(/1\.0\.0/, stdout)
      end
    end

    def test_check_code_fix_uses_custom_version_literal_pattern
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")
        path = write_file(File.join("lib", "my_gem", "constants.rb"), <<~RUBY)
          release "2.0.0"
          EXAMPLE = "1.0.0"
        RUBY

        Task.new do |config|
          config.version_code_reference_files = Rake::FileList["lib/**/*.rb"]
          config.version_code_reference_pattern = /release ["'](?<version>\d+\.\d+\.\d+)["']/
        end

        stdout = capture_stdout { Rake::Task["semverve:fix:code"].invoke }

        assert_match(%r{Updated lib/my_gem/constants\.rb}, stdout)
        assert_match(/Replaced 1 code version literal\./, stdout)
        assert_match(/release "2\.0\.1"/, File.read(path))
        assert_match(/EXAMPLE = "1\.0\.0"/, File.read(path))
      end
    end

    def test_version_code_reference_pattern_rejects_non_regexps
      in_project do
        error = assert_raises(Error) do
          Task.new do |config|
            config.version_code_reference_pattern = "VERSION ="
          end
        end

        assert_equal "version_code_reference_pattern must be a Regexp.", error.message
      end
    end

    def test_version_code_reference_pattern_requires_version_capture
      in_project do
        error = assert_raises(Error) do
          Task.new do |config|
            config.version_code_reference_pattern = /VERSION = ["'](\d+\.\d+\.\d+)["']/
          end
        end

        assert_equal "version_code_reference_pattern must include a named capture called version.", error.message
      end
    end

    def test_check_rails_config_metadata_reports_config_x_version_literal
      in_project do
        write_simple_version("Storefront", "2.0.1", path: File.join("config", "version.rb"))
        write_file("config/application.rb", "  config.x.version = \"2.0.0\"\n")

        with_stubbed_rails(root: @tmpdir, application: rails_application("Storefront")) do
          Task.new do |config|
            config.preset = :rails
          end

          stdout, = capture_error(Error) { Rake::Task["semverve:check:rails_config_metadata"].invoke }

          assert_match(%r{config/application\.rb:1:\d+: Rails config version 2\.0\.0 -> 2\.0\.1}, stdout)
        end
      end
    end

    def test_check_rails_config_metadata_reports_rails_application_config_literal
      in_project do
        write_simple_version("Storefront", "2.0.1", path: File.join("config", "version.rb"))
        write_file("config/initializers/version.rb", "Rails.application.config.x.version = '2.0.0'\n")

        with_stubbed_rails(root: @tmpdir, application: rails_application("Storefront")) do
          Task.new do |config|
            config.preset = :rails
          end

          stdout, = capture_error(Error) { Rake::Task["semverve:check:rails_config_metadata"].invoke }

          assert_match(%r{config/initializers/version\.rb:1:\d+: Rails config version 2\.0\.0 -> 2\.0\.1}, stdout)
        end
      end
    end

    def test_fix_rails_config_metadata_rewrites_safe_literals
      in_project do
        write_simple_version("Storefront", "2.0.1", path: File.join("config", "version.rb"))
        config_path = write_file("config/environments/production.rb", "  config.x.version = \"2.0.0\"\n")

        with_stubbed_rails(root: @tmpdir, application: rails_application("Storefront")) do
          Task.new do |config|
            config.preset = :rails
          end

          stdout = capture_stdout { Rake::Task["semverve:fix:rails_config_metadata"].invoke }

          assert_match(%r{Updated config/environments/production\.rb}, stdout)
          assert_match(/Replaced 1 Rails config version\./, stdout)
          assert_equal "  config.x.version = \"2.0.1\"\n", File.read(config_path)
        end
      end
    end

    def test_rails_config_metadata_ignores_dynamic_assignments
      in_project do
        write_simple_version("Storefront", "2.0.1", path: File.join("config", "version.rb"))
        write_file("config/application.rb", "  config.x.version = Storefront::VERSION\n")

        with_stubbed_rails(root: @tmpdir, application: rails_application("Storefront")) do
          Task.new do |config|
            config.preset = :rails
          end

          assert_equal "Rails config metadata is current.\n",
            capture_stdout { Rake::Task["semverve:check:rails_config_metadata"].invoke }
        end
      end
    end

    def test_rails_config_metadata_allows_missing_assignment
      in_project do
        write_simple_version("Storefront", "2.0.1", path: File.join("config", "version.rb"))
        write_file("config/application.rb", "  config.load_defaults 8.0\n")

        with_stubbed_rails(root: @tmpdir, application: rails_application("Storefront")) do
          Task.new do |config|
            config.preset = :rails
          end

          assert_equal "Rails config metadata is current.\n",
            capture_stdout { Rake::Task["semverve:check:rails_config_metadata"].invoke }
        end
      end
    end

    def test_check_package_metadata_reports_literal_gemspec_mismatch
      in_project do
        write_gemspec("my_gem", version: "2.0.0")
        write_module_version("MyGem", "2.0.1")

        Task.new

        stdout, = capture_error(Error) { Rake::Task["semverve:check:package_metadata"].invoke }

        assert_match(/my_gem\.gemspec:\d+:\d+: gemspec version 2\.0\.0 -> 2\.0\.1/, stdout)
      end
    end

    def test_check_package_metadata_uses_configured_gem_name_with_multiple_gemspecs
      in_project do
        write_gemspec("other_gem", version: "9.9.9")
        write_gemspec("my_gem", version: "2.0.0")
        write_module_version("MyGem", "2.0.1")

        Task.new do |config|
          config.gem_name = "my_gem"
        end

        stdout, = capture_error(Error) { Rake::Task["semverve:check:package_metadata"].invoke }

        assert_match(/my_gem\.gemspec:\d+:\d+: gemspec version 2\.0\.0 -> 2\.0\.1/, stdout)
        assert_no_match(/other_gem\.gemspec/, stdout)
      end
    end

    def test_check_package_metadata_reports_lockfile_mismatch
      in_project do
        write_gemspec("my_gem", version: "2.0.1")
        write_module_version("MyGem", "2.0.1")
        write_lockfile("my_gem", "2.0.0")

        Task.new

        stdout, = capture_error(Error) { Rake::Task["semverve:check:package_metadata"].invoke }

        assert_match(/Gemfile\.lock:4:13: locked version 2\.0\.0 -> 2\.0\.1/, stdout)
      end
    end

    def test_check_package_metadata_allows_dynamic_gemspec_and_missing_lockfile
      in_project do
        write_module_version("MyGem", "2.0.1")
        write_gemspec("my_gem", dynamic: true)

        Task.new

        assert_equal "Package metadata is current.\n", capture_stdout { Rake::Task["semverve:check:package_metadata"].invoke }
      end
    end

    def test_check_package_metadata_fix_rewrites_literal_gemspec_and_runs_bundle_lock
      commands = []

      in_project do
        gemspec_path = write_gemspec("my_gem", version: "2.0.0")
        write_module_version("MyGem", "2.0.1")
        write_lockfile("my_gem", "2.0.0")

        Task.new do |config|
          config.command_runner = ->(command) { commands << command }
        end

        stdout = capture_stdout { Rake::Task["semverve:fix:package_metadata"].invoke }

        assert_match(/Updated my_gem\.gemspec/, stdout)
        assert_match(/Replaced 1 package metadata version\./, stdout)
        assert_match(/Ran bundle lock\./, stdout)
        assert_match(/spec.version = "2\.0\.1"/, File.read(gemspec_path))
        assert_equal ["bundle lock"], commands
      end
    end

    def test_check_aggregates_reference_code_and_metadata_findings
      in_project do
        write_gemspec("my_gem", version: "2.0.0")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Install version 2.0.0.\n")
        write_file(File.join("lib", "my_gem", "constants.rb"), "APP_VERSION = \"2.0.0\"\n")

        Task.new do |config|
          config.version_code_reference_files = Rake::FileList["lib/**/*.rb"]
        end

        stdout, _stderr, error = capture_error(Error) { Rake::Task["semverve:check"].invoke }

        assert_match(/README\.md:1:17: version reference 2\.0\.0 -> 2\.0\.1/, stdout)
        assert_match(%r{lib/my_gem/constants\.rb:1:16: code version literal 2\.0\.0 -> 2\.0\.1}, stdout)
        assert_match(/my_gem\.gemspec:\d+:\d+: gemspec version 2\.0\.0 -> 2\.0\.1/, stdout)
        assert_equal "Found 3 version check issues.", error.message
      end
    end

    def test_check_target_filters_references_and_code_but_not_metadata
      in_project do
        write_gemspec("my_gem", version: "2.0.0")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Target 1.9.9, old 1.0.0.\n")
        write_file(File.join("lib", "my_gem", "constants.rb"), <<~RUBY)
          TARGET_VERSION = "1.9.9"
          OLD_VERSION = "1.0.0"
        RUBY

        Task.new do |config|
          config.version_code_reference_files = Rake::FileList["lib/**/*.rb"]
        end

        stdout, _stderr, error = capture_error(Error) { Rake::Task["semverve:check"].invoke("1.9.9") }

        assert_match(/README\.md:1:8: version reference 1\.9\.9 -> 2\.0\.1/, stdout)
        assert_match(%r{lib/my_gem/constants\.rb:1:19: code version literal 1\.9\.9 -> 2\.0\.1}, stdout)
        assert_match(/my_gem\.gemspec:\d+:\d+: gemspec version 2\.0\.0 -> 2\.0\.1/, stdout)
        assert_no_match(/1\.0\.0 -> 2\.0\.1/, stdout)
        assert_equal "Found 3 version check issues.", error.message
      end
    end

    def test_check_respects_configured_version_checks
      in_project do
        write_gemspec("my_gem", version: "2.0.0")
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Install version 2.0.0.\n")
        write_file(File.join("lib", "my_gem", "constants.rb"), "APP_VERSION = \"2.0.0\"\n")

        Task.new do |config|
          config.version_checks = [:doc_references, :package_metadata]
          config.version_code_reference_files = Rake::FileList["lib/**/*.rb"]
        end

        stdout, _stderr, error = capture_error(Error) { Rake::Task["semverve:check"].invoke }

        assert_match(/README\.md:1:17: version reference 2\.0\.0 -> 2\.0\.1/, stdout)
        assert_match(/my_gem\.gemspec:\d+:\d+: gemspec version 2\.0\.0 -> 2\.0\.1/, stdout)
        refute_match(/code version literal/, stdout)
        assert_equal "Found 2 version check issues.", error.message
      end
    end

    def test_fix_respects_configured_version_checks
      commands = []

      in_project do
        gemspec_path = write_gemspec("my_gem", version: "2.0.0")
        write_module_version("MyGem", "2.0.1")
        readme_path = write_file("README.md", "Install version 2.0.0.\n")
        code_path = write_file(File.join("lib", "my_gem", "constants.rb"), "APP_VERSION = \"2.0.0\"\n")
        write_lockfile("my_gem", "2.0.0")

        Task.new do |config|
          config.command_runner = ->(command) { commands << command }
          config.version_checks = [:code_references]
          config.version_code_reference_files = Rake::FileList["lib/**/*.rb"]
        end

        stdout = capture_stdout { Rake::Task["semverve:fix"].invoke }

        assert_match(%r{Updated lib/my_gem/constants\.rb}, stdout)
        assert_match(/Replaced 1 code version literal\./, stdout)
        assert_equal "Install version 2.0.0.\n", File.read(readme_path)
        assert_match(/APP_VERSION = "2\.0\.1"/, File.read(code_path))
        assert_match(/spec.version = "2\.0\.0"/, File.read(gemspec_path))
        assert_empty commands
      end
    end

    def test_version_checks_rejects_unknown_checks
      in_project do
        error = assert_raises(Error) do
          Task.new do |config|
            config.version_checks = [:package_metadata, :everything]
          end
        end

        assert_equal "Unknown version check :everything. Use :doc_references, :code_references, :package_metadata, or :rails_config_metadata.", error.message
      end
    end

    def test_version_checks_rejects_removed_metadata_check
      in_project do
        error = assert_raises(Error) do
          Task.new do |config|
            config.version_checks = [:metadata]
          end
        end

        assert_equal "Unknown version check :metadata. Use :doc_references, :code_references, :package_metadata, or :rails_config_metadata.", error.message
      end
    end

    def test_release_checks_default_to_empty
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")

        Task.new

        assert_equal "Release checks passed.\n", capture_stdout { Rake::Task["semverve:check:release"].invoke }
      end
    end

    def test_check_release_runs_configured_rubygems_check
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")

        Task.new do |config|
          config.release_checks = [:rubygems]
        end

        with_stubbed_rubygems_response(200, [{"number" => "2.0.0"}]) do
          assert_equal "Release checks passed.\n", capture_stdout { Rake::Task["semverve:check:release"].invoke }
        end
      end
    end

    def test_check_release_fails_when_configured_rubygems_check_finds_current_version
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")

        Task.new do |config|
          config.release_checks = ["rubygems"]
        end

        with_stubbed_rubygems_response(200, [{"number" => "2.0.1"}]) do
          error = assert_raise(Error) { Rake::Task["semverve:check:release"].invoke }

          assert_equal "my_gem 2.0.1 already exists on https://rubygems.org.", error.message
        end
      end
    end

    def test_check_rubygems_runs_even_when_release_checks_are_empty
      in_project do
        write_gemspec("my_gem")
        write_module_version("MyGem", "2.0.1")

        Task.new

        with_stubbed_rubygems_response(200, [{"number" => "2.0.0"}]) do
          assert_equal(
            "my_gem 2.0.1 is not published on https://rubygems.org.\n",
            capture_stdout { Rake::Task["semverve:check:rubygems"].invoke }
          )
        end
      end
    end

    def test_check_does_not_run_release_checks
      in_project do
        write_gemspec("my_gem", dynamic: true)
        write_module_version("MyGem", "2.0.1")
        write_file("README.md", "Install version 2.0.1.\n")

        Task.new do |config|
          config.release_checks = [:rubygems]
        end

        with_stubbed_rubygems_network_error(RuntimeError.new("release check should not run")) do
          assert_equal "Version checks passed.\n", capture_stdout { Rake::Task["semverve:check"].invoke }
        end
      end
    end

    def test_release_checks_rejects_unknown_checks
      in_project do
        error = assert_raises(Error) do
          Task.new do |config|
            config.release_checks = [:rubygems, :everything]
          end
        end

        assert_equal "Unknown release check :everything. Use :rubygems.", error.message
      end
    end

    def test_check_fix_dispatches_all_fixers
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

        stdout = capture_stdout { Rake::Task["semverve:fix"].invoke }

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

    def rails_application(module_name)
      Class.new do
        define_singleton_method(:module_parent_name) { module_name }
      end.new
    end

    def with_stubbed_rails(root:, application:)
      original_rails = Object.const_get(:Rails) if Object.const_defined?(:Rails)
      Object.send(:remove_const, :Rails) if Object.const_defined?(:Rails)

      railtie = Class.new do
        class << self
          def rake_tasks(&block)
            rake_tasks_blocks << block
          end

          def rake_tasks_blocks
            @rake_tasks_blocks ||= []
          end
        end
      end

      rails = Module.new
      rails.const_set(:Railtie, railtie)
      rails.define_singleton_method(:root) { root }
      rails.define_singleton_method(:application) { application }
      Object.const_set(:Rails, rails)

      yield rails
    ensure
      Object.send(:remove_const, :Rails) if Object.const_defined?(:Rails)
      Object.const_set(:Rails, original_rails) if defined?(original_rails)
    end

    def write_file(path, content)
      full_path = File.join(@tmpdir, path)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)
      full_path
    end

    def with_stubbed_rubygems_response(code, body)
      response = Struct.new(:code, :body).new(code.to_s, JSON.generate(body))
      original = PublishedVersion.http_getter

      PublishedVersion.http_getter = ->(_uri) { response }

      yield
    ensure
      PublishedVersion.http_getter = original
    end

    def with_stubbed_rubygems_network_error(error)
      original = PublishedVersion.http_getter

      PublishedVersion.http_getter = ->(_uri) do
        raise error
      end

      yield
    ensure
      PublishedVersion.http_getter = original
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

    def with_argv(values)
      original = ARGV.dup
      ARGV.replace(values)

      yield
    ensure
      ARGV.replace(original)
    end
  end
end
