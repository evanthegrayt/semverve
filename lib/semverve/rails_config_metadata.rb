# frozen_string_literal: true

require "rake"

require_relative "file_list_resolver"
require_relative "finding"
require_relative "fix_result"
require_relative "semantic_version"
require_relative "version_literal_rewriter"
require_relative "version_match_policy"

module Semverve
  ##
  # Finds and updates Rails-native config version literals.
  class RailsConfigMetadata
    ##
    # Default Rails config file patterns that can expose an app version.
    #
    # @return [Array<String>]
    DEFAULT_FILE_PATTERNS = [
      "config/application.rb",
      "config/environments/*.rb",
      "config/initializers/**/*.rb"
    ].freeze

    ##
    # Rails config version assignments that are safe to rewrite.
    #
    # @return [Regexp]
    VERSION_PATTERN = /^\s*(?:Rails\.application\.)?config\.x\.version\s*=\s*(?<quote>["'])(?<version>\d+\.\d+\.\d+)\k<quote>/

    ##
    # Initializes Rails config metadata scanning.
    #
    # @param [Semverve::ResolvedConfiguration] configuration
    # @param [Semverve::SemanticVersion] current_version
    #
    # @return [Semverve::RailsConfigMetadata]
    def initialize(configuration, current_version)
      @configuration = configuration
      @current_version = current_version
    end

    ##
    # Rails config metadata findings.
    #
    # @return [Array<Semverve::Finding>]
    def findings
      files.flat_map { |path| findings_for_file(path) }
    end

    ##
    # Replaces safe stale Rails config version literals with the current version.
    #
    # @return [Semverve::FixResult]
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

      Semverve::FixResult.new(changed_files: changed_files, replacement_count: replacement_count)
    end

    private

    ##
    # Resolved Semverve configuration.
    #
    # @return [Semverve::ResolvedConfiguration]
    attr_reader :configuration

    ##
    # Current app version.
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
      @files ||= FileListResolver.new(root: root, file_list: Rake::FileList[*DEFAULT_FILE_PATTERNS]).files
    end

    ##
    # Findings for a single file.
    #
    # @param [String] path
    #
    # @return [Array<Semverve::Finding>]
    def findings_for_file(path)
      File.readlines(path).filter_map.with_index(1) do |line, line_number|
        match = line.match(VERSION_PATTERN)
        next unless match

        version = SemanticVersion.parse(match[:version])
        next unless match_policy.report?(version)

        Semverve::Finding.new(
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
        match = line.match(VERSION_PATTERN)
        next line unless match

        version = SemanticVersion.parse(match[:version])
        next line unless match_policy.report?(version)

        replacement_count += 1
        literal_rewriter.rewrite(line)
      end.join

      [fixed, replacement_count]
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

    ##
    # Rails config metadata always requires an exact current-version match.
    #
    # @return [Semverve::VersionMatchPolicy]
    def match_policy
      @match_policy ||= VersionMatchPolicy.new(current_version: current_version, match_mode: :non_current)
    end

    ##
    # Safe literal rewriter for Rails config metadata.
    #
    # @return [Semverve::VersionLiteralRewriter]
    def literal_rewriter
      @literal_rewriter ||= VersionLiteralRewriter.new(pattern: VERSION_PATTERN, replacement: current_version)
    end
  end
end
