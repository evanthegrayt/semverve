# frozen_string_literal: true

require_relative "error"

module Semverve
  class ProjectMetadata
    def initialize(configuration)
      @configuration = configuration
    end

    def gem_name
      explicit_gem_name || version_file_gem_name || gemspec_name
    end

    def module_name
      explicit_module_name || camelize(gem_name)
    end

    def version_file
      explicit_version_file || File.join("lib", gem_name, "version.rb")
    end

    private

    attr_reader :configuration

    def explicit_gem_name
      configuration.gem_name
    end

    def explicit_module_name
      configuration.module_name
    end

    def explicit_version_file
      configuration.version_file
    end

    def version_file_gem_name
      return unless explicit_version_file

      File.basename(File.dirname(explicit_version_file))
    end

    def gemspec_name
      gemspec_file.then { |file| extract_name(file) }
    end

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

    def extract_name(file)
      content = File.read(file)
      match = content.match(/^\s*\w+\.name\s*=\s*["']([^"']+)["']/)

      return match[1] if match

      raise Error, "Could not infer gem name from #{file}. Set config.gem_name."
    end

    def camelize(value)
      value.split(/[_-]/).map(&:capitalize).join
    end
  end
end
