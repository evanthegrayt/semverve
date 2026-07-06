# frozen_string_literal: true

require_relative "../error"
require_relative "../semantic_version"

module Semverve
  module Formats
    ##
    # Handles version files that define a single top-level +VERSION+ string.
    class SimpleString
      ##
      # Pattern for locating a simple +VERSION+ assignment.
      #
      # @return [Regexp]
      PATTERN = /^(\s*VERSION\s*=\s*)(["'])(\d+\.\d+\.\d+)(\2)/

      ##
      # Parses a semantic version from simple string content.
      #
      # @param [String] content
      # @param [String] path
      #
      # @return [Semverve::SemanticVersion]
      def parse(content, path:)
        match = content.match(PATTERN)

        return SemanticVersion.parse(match[3]) if match

        raise Error, "Could not parse #{path} as simple format. Expected VERSION = \"MAJOR.MINOR.PATCH\"."
      end

      ##
      # Replaces the semantic version in simple string content.
      #
      # @param [String] content
      # @param [Semverve::SemanticVersion] version
      # @param [String] path
      #
      # @return [String]
      def replace(content, version, path:)
        unless content.match?(PATTERN)
          raise Error, "Could not parse #{path} as simple format. Expected VERSION = \"MAJOR.MINOR.PATCH\"."
        end

        content.sub(PATTERN) { "#{$1}#{$2}#{version}#{$4}" }
      end

      ##
      # Generates a simple version file.
      #
      # @param [Semverve::SemanticVersion] version
      # @param [String] module_name
      #
      # @return [String]
      def generate(version, module_name:)
        <<~RUBY
          # frozen_string_literal: true

          ##
          # Namespace for #{module_name}.
          module #{module_name}
            ##
            # Full gem version string.
            #
            # @return [String]
            VERSION = "#{version}"
          end
        RUBY
      end
    end
  end
end
