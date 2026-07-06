# frozen_string_literal: true

require_relative "configuration"
require_relative "file_list_resolver"
require_relative "semantic_version"

module Semverve
  ##
  # Finds and updates safe version literals in configured code files.
  class VersionCodeReferences
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
    def initialize(configuration, current_version)
      @configuration = configuration
      @current_version = current_version
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
      File.readlines(path).filter_map.with_index(1) do |line, line_number|
        match = line.match(pattern)
        next unless match

        version = SemanticVersion.parse(match[:version])
        next if version == current_version

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

      fixed = content.lines.map do |line|
        match = line.match(pattern)
        next line unless match

        version = SemanticVersion.parse(match[:version])
        next line if version == current_version

        replacement_count += 1
        replace_matched_version(line)
      end.join

      [fixed, replacement_count]
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
