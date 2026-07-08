# frozen_string_literal: true

require_relative "error"

module Semverve
  ##
  # Formats Semverve task results for Rake users.
  class TaskReporter
    ##
    # Initializes a task reporter.
    #
    # @param [#puts] output
    # @param [#puts] error_output
    #
    # @return [Semverve::TaskReporter]
    def initialize(output: nil, error_output: nil)
      @output = output || $stdout
      @error_output = error_output || $stderr
    end

    ##
    # Prints check findings and raises when mismatches exist.
    #
    # @param [Semverve::VersionAudit::CheckResult] result
    # @param [String, nil] fix_task_name
    #
    # @return [void]
    def report_check(result, fix_task_name: nil)
      if result.clean?
        output.puts result.clean_message
        return
      end

      result.findings.each do |labeled_finding|
        finding = labeled_finding.finding
        output.puts "#{finding.path}:#{finding.line}:#{finding.column}: #{labeled_finding.label} #{finding.version} -> #{result.current_version}"
      end

      if result.current_target_fix_noop_notice? && fix_task_name
        output.puts "Target version #{result.target_version} is already current; #{fix_task_name}[#{result.target_version}] will not change these references."
      end

      issue = result.findings.one? ? "issue" : "issues"
      raise Error, "Found #{result.findings.count} version check #{issue}."
    end

    ##
    # Prints fix results.
    #
    # @param [Semverve::VersionAudit::FixResult] result
    #
    # @return [void]
    def report_fix(result)
      if result.noop?
        output.puts "Target version #{result.target_version} is already current; nothing to fix."
        return
      end

      if result.clean?
        output.puts result.clean_message
        return
      end

      result.groups.each do |group|
        group.result.changed_files.each { |path| output.puts "Updated #{path}" }
        next if group.result.replacement_count.zero?

        noun = (group.result.replacement_count == 1) ? group.label : "#{group.label}s"
        output.puts "Replaced #{group.result.replacement_count} #{noun}."
      end

      output.puts "Ran bundle lock." if result.bundle_lock_ran?
    end

    ##
    # Reports a version-file update and runs configured follow-up commands.
    #
    # @param [Semverve::VersionFile::UpdateResult] update
    # @param [Semverve::ResolvedConfiguration] configuration
    #
    # @return [void]
    def report_update(update, configuration)
      unless update.changed?
        output.puts "Version is already #{update.version}"
        return
      end

      if update.version < update.previous_version
        error_output.puts "Warning: updating to version #{update.version}, which is lower than the current version #{update.previous_version}."
      end

      output.puts "Updating to version #{update.version} (was #{update.previous_version})"
      configuration.command_runner.call("bundle lock") if configuration.bundle_lock
    end

    private

    ##
    # Standard output stream.
    #
    # @return [#puts]
    attr_reader :output

    ##
    # Standard error stream.
    #
    # @return [#puts]
    attr_reader :error_output
  end
end
