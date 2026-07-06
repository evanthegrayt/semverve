# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/semverve/formats"

module Semverve
  class FormatsTest < Test::Unit::TestCase
    def test_fetch_rejects_unknown_format
      error = assert_raise(Error) { Formats.fetch(:unknown) }

      assert_equal "Unknown version format :unknown. Use :module or :simple.", error.message
    end

    def test_module_format_parse_requires_all_constants
      error = assert_raise(Error) do
        Formats::ModuleConstants.new.parse("MAJOR = 1\nMINOR = 2\n", path: "version.rb")
      end

      assert_equal "Could not parse version.rb as module format. Expected PATCH = <integer>.", error.message
    end

    def test_module_format_replace_requires_all_constants
      version = SemanticVersion.parse("1.2.3")

      error = assert_raise(Error) do
        Formats::ModuleConstants.new.replace("MAJOR = 0\nMINOR = 1\n", version, path: "version.rb")
      end

      assert_equal "Could not find PATCH in version.rb.", error.message
    end

    def test_simple_format_replace_requires_version_assignment
      version = SemanticVersion.parse("1.2.3")

      error = assert_raise(Error) do
        Formats::SimpleString.new.replace("VERSION = \"soon\"\n", version, path: "version.rb")
      end

      assert_equal "Could not parse version.rb as simple format. Expected VERSION = \"MAJOR.MINOR.PATCH\".", error.message
    end
  end
end
