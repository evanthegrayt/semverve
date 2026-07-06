# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/semverve/semantic_version"

module Semverve
  class SemanticVersionTest < Test::Unit::TestCase
    def test_compares_major_versions
      assert_operator SemanticVersion.parse("2.0.0"), :>, SemanticVersion.parse("1.9.9")
      assert_operator SemanticVersion.parse("1.9.9"), :<, SemanticVersion.parse("2.0.0")
    end

    def test_compares_minor_versions
      assert_operator SemanticVersion.parse("1.2.0"), :>, SemanticVersion.parse("1.1.9")
      assert_operator SemanticVersion.parse("1.1.9"), :<, SemanticVersion.parse("1.2.0")
    end

    def test_compares_patch_versions
      assert_operator SemanticVersion.parse("1.2.3"), :>, SemanticVersion.parse("1.2.2")
      assert_operator SemanticVersion.parse("1.2.2"), :<, SemanticVersion.parse("1.2.3")
    end

    def test_compares_equal_versions
      assert_equal SemanticVersion.parse("1.2.3"), SemanticVersion.parse("1.2.3")
    end

    def test_parse_rejects_invalid_versions
      error = assert_raise(Error) { SemanticVersion.parse("1.2") }

      assert_equal "Expected a semantic version in MAJOR.MINOR.PATCH format, got \"1.2\".", error.message
    end

    def test_increment_rejects_unknown_level
      error = assert_raise(Error) { SemanticVersion.parse("1.2.3").increment(:build) }

      assert_equal "Unknown version increment level: :build.", error.message
    end
  end
end
