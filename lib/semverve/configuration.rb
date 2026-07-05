# frozen_string_literal: true

require_relative "project_metadata"

module Semverve
  class Configuration
    attr_accessor :bundle_lock,
      :command_runner,
      :format,
      :gem_name,
      :module_name,
      :root,
      :version_file

    def initialize
      @bundle_lock = false
      @command_runner = ->(command) { system(command) }
      @format = :module
    end

    def resolved
      metadata = ProjectMetadata.new(self)

      ResolvedConfiguration.new(
        bundle_lock: bundle_lock,
        command_runner: command_runner,
        format: normalized_format,
        gem_name: metadata.gem_name,
        module_name: metadata.module_name,
        root: expanded_root,
        version_file: metadata.version_file
      )
    end

    def expanded_root
      File.expand_path(root || Dir.pwd)
    end

    def normalized_format
      format.to_sym
    end
  end

  class ResolvedConfiguration
    attr_reader :bundle_lock,
      :command_runner,
      :format,
      :gem_name,
      :module_name,
      :root,
      :version_file

    def initialize(bundle_lock:, command_runner:, format:, gem_name:, module_name:, root:, version_file:)
      @bundle_lock = bundle_lock
      @command_runner = command_runner
      @format = format
      @gem_name = gem_name
      @module_name = module_name
      @root = root
      @version_file = version_file
    end

    def absolute_version_file
      File.expand_path(version_file, root)
    end
  end
end
