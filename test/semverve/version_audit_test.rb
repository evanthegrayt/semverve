# frozen_string_literal: true

require "fileutils"
require "tmpdir"

require_relative "../test_helper"

module Semverve
  class VersionAuditTest < Test::Unit::TestCase
    class FakeCheck < VersionChecks::Check
      attr_reader :finding_calls, :fix_calls

      def initialize(name:, task_name: nil, targetable: false, findings: [], fix_result: nil, exact_notice: false)
        @name = name
        @task_name = task_name || name
        @targetable = targetable
        @findings = findings
        @fix_result = fix_result || Semverve::FixResult.new(changed_files: [], replacement_count: 0)
        @exact_notice = exact_notice
        @finding_calls = []
        @fix_calls = []
      end

      attr_reader :name, :task_name

      def check_description
        "Check #{name}"
      end

      def fix_description
        "Fix #{name}"
      end

      def finding_label
        "#{name} finding"
      end

      def clean_message
        "#{name} clean."
      end

      def targetable?
        @targetable
      end

      def exact_target_fix_noop_notice?
        @exact_notice
      end

      def findings(configuration, current_version, include_ignored: false, target_version: nil)
        finding_calls << [configuration, current_version, include_ignored, target_version]
        @findings
      end

      def fix(configuration, current_version, target_version: nil)
        fix_calls << [configuration, current_version, target_version]
        @fix_result
      end
    end

    def setup
      @tmpdir = Dir.mktmpdir
      write_version_file("2.0.1")
    end

    def teardown
      FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
    end

    def test_umbrella_check_returns_grouped_and_flat_findings
      current_version = SemanticVersion.parse("2.0.1")
      stale_version = SemanticVersion.parse("2.0.0")
      first_finding = Finding.new(path: "README.md", line: 1, column: 1, version: stale_version)
      second_finding = Finding.new(path: "lib/example.rb", line: 2, column: 9, version: stale_version)
      first_check = FakeCheck.new(name: :first, findings: [first_finding])
      second_check = FakeCheck.new(name: :second, findings: [second_finding])
      audit = VersionAudit.new(configuration: configuration(version_checks: [:first, :second]), checks: [first_check, second_check])

      result = audit.check

      refute result.clean?
      assert_equal current_version, result.current_version
      assert_equal [:first, :second], result.groups.map { |group| group.check.name }
      assert_equal [first_finding, second_finding], result.findings.map(&:finding)
      assert_equal ["first finding", "second finding"], result.findings.map(&:label)
      assert_equal [first_check, second_check], result.findings.map(&:check)
    end

    def test_focused_check_runs_only_the_named_check
      first_check = FakeCheck.new(name: :first)
      second_check = FakeCheck.new(name: :second, task_name: :seconds)
      audit = VersionAudit.new(configuration: configuration(version_checks: [:first, :second]), checks: [first_check, second_check])

      result = audit.check_one(:seconds)

      assert result.clean?
      assert_equal [:second], result.groups.map { |group| group.check.name }
      assert_empty first_check.finding_calls
      assert_equal 1, second_check.finding_calls.length
    end

    def test_target_version_and_include_ignored_are_passed_to_targetable_checks_only
      target_version = SemanticVersion.parse("1.9.9")
      targetable_check = FakeCheck.new(name: :targetable, targetable: true)
      plain_check = FakeCheck.new(name: :plain)
      config = configuration(version_checks: [:targetable, :plain])
      audit = VersionAudit.new(configuration: config, checks: [targetable_check, plain_check], include_ignored: true)

      audit.check(target_version: target_version)
      audit.fix(target_version: target_version)

      assert_equal [config, SemanticVersion.parse("2.0.1"), true, target_version], targetable_check.finding_calls.first
      assert_equal [config, SemanticVersion.parse("2.0.1"), true, nil], plain_check.finding_calls.first
      assert_equal [config, SemanticVersion.parse("2.0.1"), target_version], targetable_check.fix_calls.first
      assert_equal [config, SemanticVersion.parse("2.0.1"), nil], plain_check.fix_calls.first
    end

    def test_fix_current_target_returns_noop_without_running_fixers
      current_version = SemanticVersion.parse("2.0.1")
      check = FakeCheck.new(name: :targetable, targetable: true)
      audit = VersionAudit.new(configuration: configuration(version_checks: [:targetable]), checks: [check])

      result = audit.fix(target_version: current_version)

      assert result.noop?
      assert result.clean?
      assert_empty result.groups
      assert_empty check.fix_calls
    end

    def test_adapter_checks_are_available_to_programmatic_audits
      audit = VersionAudit.new(
        configuration: configuration(version_checks: [:rails_config_metadata]),
        checks: VersionChecks.all(extra_checks: Adapters.checks)
      )

      result = audit.check_one(:rails_config_metadata)

      assert result.clean?
      assert_equal [:rails_config_metadata], result.groups.map { |group| group.check.name }
    end

    private

    def configuration(version_checks:)
      ResolvedConfiguration.new(
        bundle_lock: false,
        command_runner: ->(_command) {},
        format: :module,
        gem_name: "my_gem",
        module_name: "MyGem",
        release_checks: [],
        root: @tmpdir,
        rubygems_host: "https://rubygems.org",
        task_namespace: "semverve",
        version_file: File.join("lib", "my_gem", "version.rb"),
        version_checks: version_checks,
        version_code_reference_files: Rake::FileList[],
        version_code_reference_pattern: VersionCodeReferences::RUBY_ASSIGNMENT_PATTERN,
        version_doc_reference_files: Rake::FileList[],
        version_match_mode: :older
      )
    end

    def write_version_file(version)
      parsed = SemanticVersion.parse(version)
      path = File.join(@tmpdir, "lib", "my_gem", "version.rb")

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, Formats::ModuleConstants.new.generate(parsed, module_name: "MyGem"))
    end
  end
end
