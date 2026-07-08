# frozen_string_literal: true

require "stringio"

require_relative "../test_helper"
require_relative "../../lib/semverve/task_reporter"

module Semverve
  class TaskReporterTest < Test::Unit::TestCase
    class FakeCheck < VersionChecks::Check
      def initialize(name:, label:, exact_notice: false)
        @name = name
        @label = label
        @exact_notice = exact_notice
      end

      attr_reader :name

      def task_name
        name
      end

      def finding_label
        label
      end

      def clean_message
        "clean."
      end

      def exact_target_fix_noop_notice?
        @exact_notice
      end

      private

      attr_reader :label
    end

    def setup
      @stdout = StringIO.new
      @stderr = StringIO.new
      @reporter = TaskReporter.new(output: @stdout, error_output: @stderr)
      @current_version = SemanticVersion.parse("2.0.1")
      @stale_version = SemanticVersion.parse("2.0.0")
    end

    def test_report_check_prints_clean_message
      result = VersionAudit::CheckResult.new(
        current_version: @current_version,
        target_version: nil,
        groups: [],
        clean_message: "Version checks passed."
      )

      @reporter.report_check(result)

      assert_equal "Version checks passed.\n", @stdout.string
    end

    def test_report_check_prints_findings_and_raises_singular_issue
      finding = Finding.new(path: "README.md", line: 1, column: 17, version: @stale_version)
      result = check_result(findings: [finding], check: FakeCheck.new(name: :doc_references, label: "version reference"))

      error = assert_raise(Error) { @reporter.report_check(result) }

      assert_equal "README.md:1:17: version reference 2.0.0 -> 2.0.1\n", @stdout.string
      assert_equal "Found 1 version check issue.", error.message
    end

    def test_report_check_raises_plural_issues
      first = Finding.new(path: "README.md", line: 1, column: 17, version: @stale_version)
      second = Finding.new(path: "CHANGELOG.md", line: 2, column: 4, version: @stale_version)
      result = check_result(findings: [first, second], check: FakeCheck.new(name: :doc_references, label: "version reference"))

      error = assert_raise(Error) { @reporter.report_check(result) }

      assert_equal "Found 2 version check issues.", error.message
    end

    def test_report_check_prints_exact_current_target_noop_notice
      finding = Finding.new(path: "README.md", line: 1, column: 17, version: @current_version)
      check = FakeCheck.new(name: :doc_references, label: "version reference", exact_notice: true)
      result = check_result(findings: [finding], check: check, target_version: @current_version)

      assert_raise(Error) { @reporter.report_check(result, fix_task_name: "semverve:fix:references") }

      assert_match(/README\.md:1:17: version reference 2\.0\.1 -> 2\.0\.1/, @stdout.string)
      assert_match(
        /Target version 2\.0\.1 is already current; semverve:fix:references\[2\.0\.1\] will not change these references\./,
        @stdout.string
      )
    end

    def test_report_fix_prints_clean_message
      result = VersionAudit::FixResult.new(
        current_version: @current_version,
        target_version: nil,
        groups: [],
        clean_message: "Version checks passed."
      )

      @reporter.report_fix(result)

      assert_equal "Version checks passed.\n", @stdout.string
    end

    def test_report_fix_prints_changed_files_replacement_counts_and_bundle_lock
      check = FakeCheck.new(name: :package_metadata, label: "package metadata version")
      changed_result = Semverve::FixResult.new(
        changed_files: ["README.md"],
        replacement_count: 2,
        bundle_lock_ran: true
      )
      result = VersionAudit::FixResult.new(
        current_version: @current_version,
        target_version: nil,
        groups: [
          VersionAudit::FixResultGroup.new(check: check, label: "package metadata version", result: changed_result)
        ],
        clean_message: "Version checks passed."
      )

      @reporter.report_fix(result)

      assert_equal(
        "Updated README.md\nReplaced 2 package metadata versions.\nRan bundle lock.\n",
        @stdout.string
      )
    end

    def test_report_fix_prints_exact_current_target_noop_message
      result = VersionAudit::FixResult.new(
        current_version: @current_version,
        target_version: @current_version,
        groups: [],
        clean_message: "Version checks passed.",
        noop: true
      )

      @reporter.report_fix(result)

      assert_equal "Target version 2.0.1 is already current; nothing to fix.\n", @stdout.string
    end

    private

    def check_result(findings:, check:, target_version: nil)
      VersionAudit::CheckResult.new(
        current_version: @current_version,
        target_version: target_version,
        groups: [
          VersionAudit::FindingGroup.new(
            check: check,
            label: check.finding_label,
            findings: findings
          )
        ],
        clean_message: "clean."
      )
    end
  end
end
