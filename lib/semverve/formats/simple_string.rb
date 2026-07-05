# frozen_string_literal: true

require_relative "../error"
require_relative "../semantic_version"

module Semverve
  module Formats
    class SimpleString
      PATTERN = /^(\s*VERSION\s*=\s*)(["'])(\d+\.\d+\.\d+)(\2)/

      def parse(content, path:)
        match = content.match(PATTERN)

        return SemanticVersion.parse(match[3]) if match

        raise Error, "Could not parse #{path} as simple format. Expected VERSION = \"MAJOR.MINOR.PATCH\"."
      end

      def replace(content, version, path:)
        unless content.match?(PATTERN)
          raise Error, "Could not parse #{path} as simple format. Expected VERSION = \"MAJOR.MINOR.PATCH\"."
        end

        content.sub(PATTERN) { "#{$1}#{$2}#{version}#{$4}" }
      end

      def generate(version, module_name:)
        <<~RUBY
          # frozen_string_literal: true

          module #{module_name}
            VERSION = "#{version}"
          end
        RUBY
      end
    end
  end
end
