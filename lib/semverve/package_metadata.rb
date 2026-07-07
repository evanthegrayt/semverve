# frozen_string_literal: true

require "rubygems"

require_relative "finding"
require_relative "fix_result"
require_relative "semantic_version"

module Semverve
  ##
  # Checks generated package metadata against the configured version file.
  class PackageMetadata
    ##
    # Literal gemspec version assignments that can be safely rewritten.
    #
    # @return [Regexp]
    GEMSPEC_LITERAL_PATTERN = /^(\s*\w+\.version\s*=\s*)(["'])(\d+\.\d+\.\d+)(\2)/

    ##
    # Initializes package metadata version checking.
    #
    # @param [Semverve::ResolvedConfiguration] configuration
    # @param [Semverve::SemanticVersion] current_version
    #
    # @return [Semverve::PackageMetadata]
    def initialize(configuration, current_version)
      @configuration = configuration
      @current_version = current_version
    end

    ##
    # Package metadata mismatches.
    #
    # @return [Array<Semverve::Finding>]
    def findings
      [gemspec_finding, lockfile_finding].compact
    end

    ##
    # Fixes safe package metadata mismatches.
    #
    # @return [Semverve::FixResult]
    def fix
      changed_files = []
      replacement_count = fix_gemspec_literal

      changed_files << relative_path(gemspec_file) if replacement_count.positive?

      bundle_lock_ran = lockfile_finding ? run_bundle_lock : false

      Semverve::FixResult.new(
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
    # Current package version.
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
    # @return [Semverve::Finding, nil]
    def gemspec_finding
      return unless gemspec_file && gemspec_version
      return if gemspec_version == current_version

      line, column = gemspec_position

      Semverve::Finding.new(
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
    # @return [Semverve::Finding, nil]
    def lockfile_finding
      return unless File.file?(lockfile_path)

      version = lockfile_version
      return unless version
      return if version == current_version

      line, column = lockfile_position(version)

      Semverve::Finding.new(
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
      return unless configuration.gem_name

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
      return unless configuration.gem_name

      File.readlines(lockfile_path).each do |line|
        match = line.match(lockfile_line_pattern)
        return SemanticVersion.parse(match[:version]) if match
      end

      nil
    end

    ##
    # Line and column for lockfile output.
    #
    # @param [Semverve::SemanticVersion] version
    #
    # @return [Array(Integer, Integer)]
    def lockfile_position(version)
      File.readlines(lockfile_path).each_with_index do |line, index|
        match = line.match(lockfile_line_pattern(version))
        return [index + 1, line.index(version.to_s) + 1] if match
      end

      [1, 1]
    end

    ##
    # Gemfile.lock line pattern for the configured package.
    #
    # @param [Semverve::SemanticVersion, nil] version
    #
    # @return [Regexp]
    def lockfile_line_pattern(version = nil)
      version_pattern = version ? Regexp.escape(version.to_s) : "\\d+\\.\\d+\\.\\d+"
      /^\s*#{Regexp.escape(configuration.gem_name)}\s+\((?<version>#{version_pattern})\)/
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
