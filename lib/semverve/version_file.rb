# frozen_string_literal: true

require_relative "error"
require_relative "formats"

module Semverve
  class VersionFile
    def initialize(configuration)
      @configuration = configuration
      @format = Formats.fetch(configuration.format)
    end

    def current
      format.parse(read, path: path)
    end

    def increment(level)
      next_version = current.increment(level)

      File.write(path, format.replace(read, next_version, path: path))
      next_version
    end

    private

    attr_reader :configuration, :format

    def path
      configuration.absolute_version_file
    end

    def read
      unless File.file?(path)
        raise Error, "Could not find version file #{path}. Run rake semverve:generate or set config.version_file."
      end

      File.read(path)
    end
  end
end
