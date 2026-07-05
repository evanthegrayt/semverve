# frozen_string_literal: true

require_relative "../error"
require_relative "../semantic_version"

module Semverve
  module Formats
    class ModuleConstants
      CONSTANTS = {
        major: "MAJOR",
        minor: "MINOR",
        patch: "PATCH"
      }.freeze

      def parse(content, path:)
        SemanticVersion.new(
          major: constant_value(content, path, :major),
          minor: constant_value(content, path, :minor),
          patch: constant_value(content, path, :patch)
        )
      end

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

      def generate(version, module_name:)
        <<~RUBY
          # frozen_string_literal: true

          module #{module_name}
            ##
            # Module that contains all gem version information. Follows semantic
            # versioning. Read: https://semver.org/
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

      def constant_value(content, path, part)
        constant = CONSTANTS.fetch(part)
        match = content.match(/^\s*#{constant}\s*=\s*(\d+)/)

        return match[1].to_i if match

        raise Error, "Could not parse #{path} as module format. Expected #{constant} = <integer>."
      end
    end
  end
end
