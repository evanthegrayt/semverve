# frozen_string_literal: true

require "ripper"

require_relative "error"
require_relative "semantic_version"

module Semverve
  ##
  # Finds and updates version references in configured project files.
  class VersionReferences
    ##
    # Marker that suppresses version-reference findings.
    #
    # @return [String]
    IGNORE_MARKER = "semverve:ignore-version-reference"

    ##
    # Version strings supported by Semverve.
    #
    # @return [Regexp]
    VERSION_PATTERN = /(?<![\d.])\d+\.\d+\.\d+(?!\.\d|\d)/

    ##
    # Text file extensions scanned as full content.
    #
    # @return [Array<String>]
    TEXT_EXTENSIONS = %w[.adoc .markdown .md .rdoc .txt].freeze

    ##
    # A stale or non-current version reference found in a project file.
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
      # @return [Semverve::VersionReferences::Finding]
      def initialize(path:, line:, column:, version:)
        @path = path
        @line = line
        @column = column
        @version = version
      end
    end

    ##
    # Result of fixing version references.
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
      # @return [Semverve::VersionReferences::FixResult]
      def initialize(changed_files:, replacement_count:)
        @changed_files = changed_files
        @replacement_count = replacement_count
      end
    end

    ##
    # Initializes version-reference scanning.
    #
    # @param [Semverve::ResolvedConfiguration] configuration
    # @param [Semverve::SemanticVersion] current_version
    #
    # @return [Semverve::VersionReferences]
    def initialize(configuration, current_version)
      @configuration = configuration
      @current_version = current_version
    end

    ##
    # Version-reference findings in configured files.
    #
    # @return [Array<Semverve::VersionReferences::Finding>]
    def findings
      files.flat_map { |path| findings_for_file(path) }
    end

    ##
    # Replaces found version references with the current version.
    #
    # @return [Semverve::VersionReferences::FixResult]
    def fix
      changed_files = []
      replacement_count = 0

      files.each do |path|
        content = File.read(path)
        fixed, count = fixed_content(path, content)

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
    # Absolute files to scan.
    #
    # @return [Array<String>]
    def files
      @files ||= begin
        configured_files = Dir.chdir(root) do
          configuration.version_reference_files.to_a.flat_map { |path| expand_file_list_entry(path) }
            .reject { |path| configuration.version_reference_files.excluded_from_list?(path) }
        end

        configured_files.map { |path| File.expand_path(path, root) }
          .select { |path| File.file?(path) }
          .reject { |path| ignored_path?(path) }
          .uniq
      end
    end

    ##
    # Expands glob-like entries that were appended to a Rake::FileList.
    #
    # @param [String] path
    #
    # @return [Array<String>]
    def expand_file_list_entry(path)
      matches = Dir.glob(path)

      matches.empty? ? [path] : matches
    end

    ##
    # Whether the file should always be skipped.
    #
    # @param [String] path
    #
    # @return [Boolean]
    def ignored_path?(path)
      File.expand_path(path) == File.expand_path(configuration.absolute_version_file)
    end

    ##
    # Finds references in a single file.
    #
    # @param [String] path
    #
    # @return [Array<Semverve::VersionReferences::Finding>]
    def findings_for_file(path)
      content = File.read(path)

      scannable_segments(path, content).flat_map do |segment|
        findings_for_segment(path, segment, content)
      end
    end

    ##
    # Returns fixed file content and replacement count.
    #
    # @param [String] path
    # @param [String] content
    #
    # @return [Array(String, Integer)]
    def fixed_content(path, content)
      replacements = scannable_segments(path, content).flat_map do |segment|
        replacements_for_segment(segment, content)
      end

      replacements.sort_by { |replacement| -replacement[:index] }.each do |replacement|
        content[replacement[:index], replacement[:length]] = current_version.to_s
      end

      [content, replacements.count]
    end

    ##
    # Scannable text segments for a file.
    #
    # @param [String] path
    # @param [String] content
    #
    # @return [Array<Hash>]
    def scannable_segments(path, content)
      if ruby_file?(path)
        ruby_comment_segments(content)
      elsif text_file?(path)
        text_segments(content)
      else
        []
      end
    end

    ##
    # Whether a file should be scanned as Ruby comments.
    #
    # @param [String] path
    #
    # @return [Boolean]
    def ruby_file?(path)
      File.extname(path) == ".rb"
    end

    ##
    # Whether a file should be scanned as text.
    #
    # @param [String] path
    #
    # @return [Boolean]
    def text_file?(path)
      TEXT_EXTENSIONS.include?(File.extname(path)) || File.basename(path).start_with?("README")
    end

    ##
    # Full-line text segments.
    #
    # @param [String] content
    #
    # @return [Array<Hash>]
    def text_segments(content)
      line_start_indexes(content).each_with_index.map do |index, line_index|
        line = content.lines[line_index]
        {line: line_index + 1, column: 1, index: index, text: line}
      end
    end

    ##
    # Ruby comment token segments.
    #
    # @param [String] content
    #
    # @return [Array<Hash>]
    def ruby_comment_segments(content)
      line_starts = line_start_indexes(content)

      Ripper.lex(content).select { |(_position, type, _text)| type == :on_comment }.flat_map do |(position, _type, text)|
        start_line, start_column = position
        token_index = line_starts.fetch(start_line - 1) + start_column

        split_token(text, start_line, start_column + 1, token_index)
      end
    end

    ##
    # Splits a possibly multiline token into line-level segments.
    #
    # @param [String] text
    # @param [Integer] start_line
    # @param [Integer] start_column
    # @param [Integer] start_index
    #
    # @return [Array<Hash>]
    def split_token(text, start_line, start_column, start_index)
      index = start_index

      text.lines.map.with_index do |line, offset|
        column = offset.zero? ? start_column : 1
        segment = {line: start_line + offset, column: column, index: index, text: line}
        index += line.length
        segment
      end
    end

    ##
    # Finds version references in a segment.
    #
    # @param [String] path
    # @param [Hash] segment
    # @param [String] content
    #
    # @return [Array<Semverve::VersionReferences::Finding>]
    def findings_for_segment(path, segment, content)
      references_for_segment(segment, content).map do |reference|
        Finding.new(
          path: relative_path(path),
          line: segment[:line],
          column: reference[:column],
          version: reference[:version]
        )
      end
    end

    ##
    # Replacements to make in a segment.
    #
    # @param [Hash] segment
    # @param [String] content
    #
    # @return [Array<Hash>]
    def replacements_for_segment(segment, content)
      references_for_segment(segment, content).map do |reference|
        {
          index: reference[:index],
          length: reference[:length]
        }
      end
    end

    ##
    # Version references in a segment.
    #
    # @param [Hash] segment
    # @param [String] content
    #
    # @return [Array<Hash>]
    def references_for_segment(segment, content)
      return [] if ignored_line?(segment[:line], content)

      segment[:text].to_enum(:scan, VERSION_PATTERN).filter_map do
        match = Regexp.last_match
        version = SemanticVersion.parse(match[0])

        next unless report?(version)

        {
          column: segment[:column] + match.begin(0),
          index: segment[:index] + match.begin(0),
          length: match[0].length,
          version: version
        }
      end
    end

    ##
    # Whether a referenced version should be reported.
    #
    # @param [Semverve::SemanticVersion] version
    #
    # @return [Boolean]
    def report?(version)
      case configuration.version_reference_mode
      when :older
        version < current_version
      when :non_current
        version != current_version
      else
        raise Error, "Unknown version reference mode #{configuration.version_reference_mode.inspect}. Use :older or :non_current."
      end
    end

    ##
    # Whether findings on a line should be ignored.
    #
    # @param [Integer] line
    # @param [String] content
    #
    # @return [Boolean]
    def ignored_line?(line, content)
      lines = content.lines
      return true if lines.fetch(line - 1).include?(IGNORE_MARKER)

      previous_nonblank_line = lines[0...(line - 1)].rfind { |candidate| !candidate.strip.empty? }
      previous_nonblank_line&.include?(IGNORE_MARKER)
    end

    ##
    # Starting index for each line in content.
    #
    # @param [String] content
    #
    # @return [Array<Integer>]
    def line_start_indexes(content)
      index = 0

      content.lines.map do |line|
        start = index
        index += line.length
        start
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
