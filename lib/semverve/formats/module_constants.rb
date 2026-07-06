# frozen_string_literal: true

require_relative "../error"
require_relative "../semantic_version"

module Semverve
  module Formats
    ##
    # Handles version files with MAJOR, MINOR, and PATCH constants.
    class ModuleConstants
      ##
      # Mapping of semantic-version parts to Ruby constant names.
      #
      # @return [Hash<Symbol, String>]
      CONSTANTS = {
        major: "MAJOR",
        minor: "MINOR",
        patch: "PATCH"
      }.freeze

      ##
      # Parses a semantic version from module-constant content.
      #
      # @param [String] content
      # @param [String] path
      #
      # @return [Semverve::SemanticVersion]
      def parse(content, path:)
        SemanticVersion.new(
          major: constant_value(content, path, :major),
          minor: constant_value(content, path, :minor),
          patch: constant_value(content, path, :patch)
        )
      end

      ##
      # Replaces MAJOR, MINOR, and PATCH values in module-constant content.
      #
      # @param [String] content
      # @param [Semverve::SemanticVersion] version
      # @param [String] path
      #
      # @return [String]
      def replace(content, version, path:)
        CONSTANTS.reduce(content) do |updated, (part, constant)|
          pattern = /^(\s*#{constant}\s*=\s*)\d+/
          value = version.public_send(part)

          unless updated.match?(pattern)
            raise Error, "Could not find #{constant} in #{path}."
          end

          updated.sub(pattern) { "#{$1}#{value}" }
        end
      end

      ##
      # Generates a module-constant version file.
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
            # Semantic version information for #{module_name}.
            module Version
              ##
              # Major version.
              #
              # @return [Integer]
              MAJOR = #{version.major}

              ##
              # Minor version.
              #
              # @return [Integer]
              MINOR = #{version.minor}

              ##
              # Patch version.
              #
              # @return [Integer]
              PATCH = #{version.patch}

              module_function

              ##
              # Version as +[MAJOR, MINOR, PATCH]+
              #
              # @return [Array<Integer>]
              def to_a
                [MAJOR, MINOR, PATCH]
              end

              ##
              # Version as +MAJOR.MINOR.PATCH+
              #
              # @return [String]
              def to_s
                to_a.join(".")
              end
            end

            ##
            # Full gem version string.
            #
            # @return [String]
            VERSION = #{module_name}::Version.to_s
          end
        RUBY
      end

      private

      ##
      # Extracts one semantic-version constant from content.
      #
      # @param [String] content
      # @param [String] path
      # @param [Symbol] part
      #
      # @return [Integer]
      def constant_value(content, path, part)
        constant = CONSTANTS.fetch(part)
        match = content.match(/^\s*#{constant}\s*=\s*(\d+)/)

        return match[1].to_i if match

        raise Error, "Could not parse #{path} as module format. Expected #{constant} = <integer>."
      end
    end
  end
end
