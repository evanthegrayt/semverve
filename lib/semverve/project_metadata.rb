# frozen_string_literal: true

require_relative "error"

module Semverve
  ##
  # Infers gem metadata from explicit configuration or project files.
  class ProjectMetadata
    ##
    # Initializes project metadata inference.
    #
    # @param [Semverve::Configuration] configuration
    #
    # @return [Semverve::ProjectMetadata]
    def initialize(configuration)
      @configuration = configuration
    end

    ##
    # Gem name from explicit config, the version-file path, or the gemspec.
    #
    # @return [String]
    def gem_name
      explicit_gem_name || version_file_gem_name || gemspec_name
    end

    ##
    # Ruby module name from explicit config or the resolved gem name.
    #
    # @return [String]
    def module_name
      explicit_module_name || camelize(gem_name)
    end

    ##
    # Version-file path from explicit config or the resolved gem name.
    #
    # @return [String]
    def version_file
      explicit_version_file || File.join("lib", gem_name, "version.rb")
    end

    private

    ##
    # Configuration used for metadata inference.
    #
    # @return [Semverve::Configuration]
    attr_reader :configuration

    ##
    # Explicitly configured gem name.
    #
    # @return [String, nil]
    def explicit_gem_name
      configuration.gem_name
    end

    ##
    # Explicitly configured Ruby module name.
    #
    # @return [String, nil]
    def explicit_module_name
      configuration.module_name
    end

    ##
    # Explicitly configured version-file path.
    #
    # @return [String, nil]
    def explicit_version_file
      configuration.version_file
    end

    ##
    # Gem name inferred from the parent directory of the version-file path.
    #
    # @return [String, nil]
    def version_file_gem_name
      return unless explicit_version_file

      File.basename(File.dirname(explicit_version_file))
    end

    ##
    # Gem name extracted from the single gemspec in the project root.
    #
    # @return [String]
    def gemspec_name
      gemspec_file.then { |file| extract_name(file) }
    end

    ##
    # Single gemspec file in the configured project root.
    #
    # @return [String]
    def gemspec_file
      files = Dir.glob(File.join(configuration.expanded_root, "*.gemspec"))

      return files.first if files.one?

      if files.empty?
        raise Error, "Could not infer gem name because no .gemspec file was found. " \
          "Set config.gem_name or config.version_file."
      end

      raise Error, "Could not infer gem name because multiple .gemspec files were found. " \
        "Set config.gem_name or config.version_file."
    end

    ##
    # Reads a gemspec and extracts its +spec.name+ assignment.
    #
    # @param [String] file
    #
    # @return [String]
    def extract_name(file)
      content = File.read(file)
      match = content.match(/^\s*\w+\.name\s*=\s*["']([^"']+)["']/)

      return match[1] if match

      raise Error, "Could not infer gem name from #{file}. Set config.gem_name."
    end

    ##
    # Converts a snake-case or kebab-case gem name into a Ruby module name.
    #
    # @param [String] value
    #
    # @return [String]
    def camelize(value)
      value.split(/[_-]/).map(&:capitalize).join
    end
  end
end
