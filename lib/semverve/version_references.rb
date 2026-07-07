# frozen_string_literal: true

require "ripper"

require_relative "file_list_resolver"
require_relative "finding"
require_relative "fix_result"
require_relative "semantic_version"
require_relative "version_match_policy"

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
    # Initializes version-reference scanning.
    #
    # @param [Semverve::ResolvedConfiguration] configuration
    # @param [Semverve::SemanticVersion] current_version
    #
    # @return [Semverve::VersionReferences]
    def initialize(configuration, current_version, include_ignored: false, target_version: nil)
      @configuration = configuration
      @current_version = current_version
      @include_ignored = include_ignored
      @target_version = target_version
    end

    ##
    # Version-reference findings in configured files.
    #
    # @return [Array<Semverve::Finding>]
    def findings
      files.flat_map { |path| findings_for_file(path) }
    end

    ##
    # Replaces found version references with the current version.
    #
    # @return [Semverve::FixResult]
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

      Semverve::FixResult.new(changed_files: changed_files, replacement_count: replacement_count)
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
    # Whether ignored references should be included in findings.
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
    # Absolute files to scan.
    #
    # @return [Array<String>]
    def files
      @files ||= FileListResolver.new(root: root, file_list: configuration.version_doc_reference_files).files
        .reject { |path| ignored_path?(path) }
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
    # @return [Array<Semverve::Finding>]
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
    # @return [Array<Semverve::Finding>]
    def findings_for_segment(path, segment, content)
      references_for_segment(segment, content).map do |reference|
        Semverve::Finding.new(
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
      return [] if !include_ignored && ignored_line?(segment[:line], content)

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
      return version == target_version if target_version

      match_policy.report?(version)
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

      # Ruby 3.2 and 3.3 do not support Array#rfind.
      # rubocop:disable Style/ReverseFind
      previous_nonblank_line = lines[0...(line - 1)].reverse_each.find { |candidate| !candidate.strip.empty? }
      # rubocop:enable Style/ReverseFind
      previous_nonblank_line&.include?(IGNORE_MARKER)
    end

    ##
    # Version matching behavior for references.
    #
    # @return [Semverve::VersionMatchPolicy]
    def match_policy
      @match_policy ||= VersionMatchPolicy.new(
        current_version: current_version,
        match_mode: configuration.version_match_mode,
        target_version: target_version
      )
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
