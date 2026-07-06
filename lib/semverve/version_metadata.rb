# frozen_string_literal: true

require "bundler"
require "rubygems"

require_relative "semantic_version"

module Semverve
  ##
  # Checks generated gem metadata against the configured version file.
  class VersionMetadata
    ##
    # Literal gemspec version assignments that can be safely rewritten.
    #
    # @return [Regexp]
    GEMSPEC_LITERAL_PATTERN = /^(\s*\w+\.version\s*=\s*)(["'])(\d+\.\d+\.\d+)(\2)/

    ##
    # A metadata version mismatch.
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
      # Metadata semantic version.
      #
      # @return [Semverve::SemanticVersion]
      attr_reader :version

      ##
      # Output label for the finding.
      #
      # @return [String]
      attr_reader :label

      ##
      # Initializes a finding.
      #
      # @param [String] path
      # @param [Integer] line
      # @param [Integer] column
      # @param [Semverve::SemanticVersion] version
      # @param [String] label
      #
      # @return [Semverve::VersionMetadata::Finding]
      def initialize(path:, line:, column:, version:, label:)
        @path = path
        @line = line
        @column = column
        @version = version
        @label = label
      end
    end

    ##
    # Result of fixing metadata version mismatches.
    class FixResult
      ##
      # Files changed by the fix.
      #
      # @return [Array<String>]
      attr_reader :changed_files

      ##
      # Number of literal replacements made.
      #
      # @return [Integer]
      attr_reader :replacement_count

      ##
      # Whether bundle lock was run.
      #
      # @return [Boolean]
      attr_reader :bundle_lock_ran

      ##
      # Initializes a fix result.
      #
      # @param [Array<String>] changed_files
      # @param [Integer] replacement_count
      # @param [Boolean] bundle_lock_ran
      #
      # @return [Semverve::VersionMetadata::FixResult]
      def initialize(changed_files:, replacement_count:, bundle_lock_ran:)
        @changed_files = changed_files
        @replacement_count = replacement_count
        @bundle_lock_ran = bundle_lock_ran
      end
    end

    ##
    # Initializes metadata version checking.
    #
    # @param [Semverve::ResolvedConfiguration] configuration
    # @param [Semverve::SemanticVersion] current_version
    #
    # @return [Semverve::VersionMetadata]
    def initialize(configuration, current_version)
      @configuration = configuration
      @current_version = current_version
    end

    ##
    # Metadata mismatches.
    #
    # @return [Array<Semverve::VersionMetadata::Finding>]
    def findings
      [gemspec_finding, lockfile_finding].compact
    end

    ##
    # Fixes safe metadata mismatches.
    #
    # @return [Semverve::VersionMetadata::FixResult]
    def fix
      changed_files = []
      replacement_count = fix_gemspec_literal

      changed_files << relative_path(gemspec_file) if replacement_count.positive?

      bundle_lock_ran = lockfile_finding ? run_bundle_lock : false

      FixResult.new(
        changed_files: changed_files,
        replacement_count: replacement_count,
        bundle_lock_ran: bundle_lock_ran
      )
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
    # Finding for a gemspec mismatch.
    #
    # @return [Semverve::VersionMetadata::Finding, nil]
    def gemspec_finding
      return unless gemspec_file && gemspec_version
      return if gemspec_version == current_version

      line, column = gemspec_position

      Finding.new(
        path: relative_path(gemspec_file),
        line: line,
        column: column,
        version: gemspec_version,
        label: "gemspec version"
      )
    end

    ##
    # Finding for a lockfile mismatch.
    #
    # @return [Semverve::VersionMetadata::Finding, nil]
    def lockfile_finding
      return unless File.file?(lockfile_path)

      version = lockfile_version
      return unless version
      return if version == current_version

      line, column = lockfile_position(version)

      Finding.new(
        path: "Gemfile.lock",
        line: line,
        column: column,
        version: version,
        label: "locked version"
      )
    end

    ##
    # Absolute gemspec path for the configured gem.
    #
    # @return [String, nil]
    def gemspec_file
      @gemspec_file ||= begin
        files = Dir.glob(File.join(root, "*.gemspec"))

        if files.one?
          files.first
        else
          files.find do |path|
            spec = load_gemspec(path)
            spec&.name == configuration.gem_name
          end
        end
      end
    end

    ##
    # Version loaded from the matching gemspec.
    #
    # @return [Semverve::SemanticVersion, nil]
    def gemspec_version
      @gemspec_version ||= begin
        spec = load_gemspec(gemspec_file)

        SemanticVersion.parse(spec.version.to_s) if spec&.version
      end
    end

    ##
    # Loads a gemspec.
    #
    # @param [String, nil] path
    #
    # @return [Gem::Specification, nil]
    def load_gemspec(path)
      return unless path

      Gem::Specification.load(path)
    end

    ##
    # Line and column for gemspec output.
    #
    # @return [Array(Integer, Integer)]
    def gemspec_position
      lines = File.readlines(gemspec_file)

      lines.each_with_index do |line, index|
        literal_match = line.match(GEMSPEC_LITERAL_PATTERN)
        return [index + 1, literal_match.begin(3) + 1] if literal_match

        assignment_index = line.index(/^\s*\w+\.version\s*=/)
        return [index + 1, assignment_index + 1] if assignment_index
      end

      [1, 1]
    end

    ##
    # Version parsed from Gemfile.lock.
    #
    # @return [Semverve::SemanticVersion, nil]
    def lockfile_version
      spec = lockfile_parser.specs.find { |candidate| candidate.name == configuration.gem_name }
      return unless spec

      SemanticVersion.parse(spec.version.to_s)
    end

    ##
    # Parsed Gemfile.lock.
    #
    # @return [Bundler::LockfileParser]
    def lockfile_parser
      Bundler::LockfileParser.new(File.read(lockfile_path))
    end

    ##
    # Line and column for lockfile output.
    #
    # @param [Semverve::SemanticVersion] version
    #
    # @return [Array(Integer, Integer)]
    def lockfile_position(version)
      pattern = /^\s*#{Regexp.escape(configuration.gem_name)}\s+\(#{Regexp.escape(version.to_s)}\)/

      File.readlines(lockfile_path).each_with_index do |line, index|
        match = line.match(pattern)
        return [index + 1, line.index(version.to_s) + 1] if match
      end

      [1, 1]
    end

    ##
    # Fixes a literal gemspec version assignment.
    #
    # @return [Integer]
    def fix_gemspec_literal
      return 0 unless gemspec_file

      content = File.read(gemspec_file)
      replacement_count = 0

      fixed = content.lines.map do |line|
        match = line.match(GEMSPEC_LITERAL_PATTERN)
        next line unless match

        version = SemanticVersion.parse(match[3])
        next line if version == current_version

        replacement_count += 1
        line.sub(GEMSPEC_LITERAL_PATTERN) { "#{$1}#{$2}#{current_version}#{$4}" }
      end.join

      File.write(gemspec_file, fixed) if replacement_count.positive?

      replacement_count
    end

    ##
    # Runs bundle lock through the configured command runner.
    #
    # @return [Boolean]
    def run_bundle_lock
      configuration.command_runner.call("bundle lock")
      true
    end

    ##
    # Absolute Gemfile.lock path.
    #
    # @return [String]
    def lockfile_path
      File.join(root, "Gemfile.lock")
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
