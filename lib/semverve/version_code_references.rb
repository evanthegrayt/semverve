# frozen_string_literal: true

require_relative "configuration"
require_relative "file_list_resolver"
require_relative "semantic_version"

module Semverve
  ##
  # Finds and updates safe version literals in configured code files.
  class VersionCodeReferences
    ##
    # Marker that suppresses version-reference findings.
    #
    # @return [String]
    IGNORE_MARKER = "semverve:ignore-version-reference"

    ##
    # Ruby assignments that are safe enough to rewrite automatically.
    #
    # @return [Regexp]
    RUBY_ASSIGNMENT_PATTERN = Configuration::DEFAULT_VERSION_CODE_REFERENCE_PATTERN

    ##
    # A code version literal found in a configured file.
    class Finding
      ##
      # Path relative to the configured project root.
      #
      # @return [String]
      attr_reader :path

      ##
      # One-based line number.
      #
      # @return [Integer]
      attr_reader :line

      ##
      # One-based column number.
      #
      # @return [Integer]
      attr_reader :column

      ##
      # Referenced semantic version.
      #
      # @return [Semverve::SemanticVersion]
      attr_reader :version

      ##
      # Initializes a finding.
      #
      # @param [String] path
      # @param [Integer] line
      # @param [Integer] column
      # @param [Semverve::SemanticVersion] version
      #
      # @return [Semverve::VersionCodeReferences::Finding]
      def initialize(path:, line:, column:, version:)
        @path = path
        @line = line
        @column = column
        @version = version
      end
    end

    ##
    # Result of fixing code version literals.
    class FixResult
      ##
      # Files changed by the fix.
      #
      # @return [Array<String>]
      attr_reader :changed_files

      ##
      # Number of replacements made.
      #
      # @return [Integer]
      attr_reader :replacement_count

      ##
      # Initializes a fix result.
      #
      # @param [Array<String>] changed_files
      # @param [Integer] replacement_count
      #
      # @return [Semverve::VersionCodeReferences::FixResult]
      def initialize(changed_files:, replacement_count:)
        @changed_files = changed_files
        @replacement_count = replacement_count
      end
    end

    ##
    # Initializes code version literal scanning.
    #
    # @param [Semverve::ResolvedConfiguration] configuration
    # @param [Semverve::SemanticVersion] current_version
    #
    # @return [Semverve::VersionCodeReferences]
    def initialize(configuration, current_version, include_ignored: false, target_version: nil)
      @configuration = configuration
      @current_version = current_version
      @include_ignored = include_ignored
      @target_version = target_version
    end

    ##
    # Code version literal findings in configured files.
    #
    # @return [Array<Semverve::VersionCodeReferences::Finding>]
    def findings
      files.flat_map { |path| findings_for_file(path) }
    end

    ##
    # Replaces found code version literals with the current version.
    #
    # @return [Semverve::VersionCodeReferences::FixResult]
    def fix
      changed_files = []
      replacement_count = 0

      files.each do |path|
        content = File.read(path)
        fixed, count = fixed_content(content)

        next if count.zero?

        File.write(path, fixed)
        changed_files << relative_path(path)
        replacement_count += count
      end

      FixResult.new(changed_files: changed_files, replacement_count: replacement_count)
    end

    private

    ##
    # Resolved Semverve configuration.
    #
    # @return [Semverve::ResolvedConfiguration]
    attr_reader :configuration

    ##
    # Current gem version.
    #
    # @return [Semverve::SemanticVersion]
    attr_reader :current_version

    ##
    # Whether ignored code literals should be included in findings.
    #
    # @return [Boolean]
    attr_reader :include_ignored

    ##
    # Exact version to match, when supplied by the task invocation.
    #
    # @return [Semverve::SemanticVersion, nil]
    attr_reader :target_version

    ##
    # Absolute configured project root.
    #
    # @return [String]
    def root
      configuration.root
    end

    ##
    # Configured pattern used to find code version literals.
    #
    # @return [Regexp]
    def pattern
      configuration.version_code_reference_pattern
    end

    ##
    # Absolute files to scan.
    #
    # @return [Array<String>]
    def files
      @files ||= FileListResolver.new(
        root: root,
        file_list: configuration.version_code_reference_files
      ).files.reject { |path| File.expand_path(path) == File.expand_path(configuration.absolute_version_file) }
    end

    ##
    # Findings for a single file.
    #
    # @param [String] path
    #
    # @return [Array<Semverve::VersionCodeReferences::Finding>]
    def findings_for_file(path)
      lines = File.readlines(path)

      lines.filter_map.with_index(1) do |line, line_number|
        next if !include_ignored && ignored_line?(line_number, lines)

        match = line.match(pattern)
        next unless match

        version = SemanticVersion.parse(match[:version])
        next unless report?(version)

        Finding.new(
          path: relative_path(path),
          line: line_number,
          column: match.begin(:version) + 1,
          version: version
        )
      end
    end

    ##
    # Fixed content and replacement count.
    #
    # @param [String] content
    #
    # @return [Array(String, Integer)]
    def fixed_content(content)
      replacement_count = 0
      lines = content.lines

      fixed = lines.map.with_index(1) do |line, line_number|
        next line if ignored_line?(line_number, lines)

        match = line.match(pattern)
        next line unless match

        version = SemanticVersion.parse(match[:version])
        next line unless report?(version)

        replacement_count += 1
        replace_matched_version(line)
      end.join

      [fixed, replacement_count]
    end

    ##
    # Whether findings on a line should be ignored.
    #
    # @param [Integer] line_number
    # @param [Array<String>] lines
    #
    # @return [Boolean]
    def ignored_line?(line_number, lines)
      return true if lines.fetch(line_number - 1).include?(IGNORE_MARKER)

      # Ruby 3.2 and 3.3 do not support Array#rfind.
      # rubocop:disable Style/ReverseFind
      previous_nonblank_line = lines[0...(line_number - 1)].reverse_each.find { |candidate| !candidate.strip.empty? }
      # rubocop:enable Style/ReverseFind
      previous_nonblank_line&.include?(IGNORE_MARKER)
    end

    ##
    # Whether a referenced version should be reported or fixed.
    #
    # @param [Semverve::SemanticVersion] version
    #
    # @return [Boolean]
    def report?(version)
      return version == target_version if target_version

      case configuration.version_match_mode
      when :older
        version < current_version
      when :non_current
        version != current_version
      else
        raise Error, "Unknown version match mode #{configuration.version_match_mode.inspect}. Use :older or :non_current."
      end
    end

    ##
    # Replaces only the named version capture in the first pattern match.
    #
    # @param [String] line
    #
    # @return [String]
    def replace_matched_version(line)
      line.sub(pattern) do |matched_text|
        match = Regexp.last_match
        version_start = match.begin(:version) - match.begin(0)
        version_end = match.end(:version) - match.begin(0)

        "#{matched_text[0...version_start]}#{current_version}#{matched_text[version_end..]}"
      end
    end

    ##
    # Path relative to the project root.
    #
    # @param [String] path
    #
    # @return [String]
    def relative_path(path)
      path.delete_prefix("#{root}/")
    end
  end
end
