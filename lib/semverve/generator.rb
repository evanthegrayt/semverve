# frozen_string_literal: true

require "fileutils"

require_relative "error"
require_relative "formats"
require_relative "semantic_version"

module Semverve
  class Generator
    DEFAULT_VERSION = "0.1.0"

    def initialize(configuration, env = ENV)
      @configuration = configuration
      @env = env
    end

    def generate
      version = SemanticVersion.parse(env.fetch("VERSION", DEFAULT_VERSION))
      format = Formats.fetch(env.fetch("FORMAT", configuration.format))
      path = configuration.absolute_version_file

      if File.exist?(path) && !force?
        raise Error, "Version file already exists at #{path}. Set FORCE=true to overwrite it."
      end

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, format.generate(version, module_name: configuration.module_name))

      path
    end

    private

    attr_reader :configuration, :env

    def force?
      env.fetch("FORCE", "false").match?(/\A(true|1|yes)\z/i)
    end
  end
end
