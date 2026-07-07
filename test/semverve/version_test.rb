# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/semverve/version"

module Semverve
  class VersionTest < Test::Unit::TestCase
    GEMFILE_VERSION_REGEX = %r{^\s*semverve\s+\(#{Semverve::VERSION}\)}o

    def test_version_exists_and_follows_semantic_versioning
      assert Semverve::VERSION
      assert_equal "0.4.1", Semverve::VERSION
      assert_match Semverve::Version.to_s, Semverve::VERSION
    end

    def test_to_a
      assert_instance_of(Array, Semverve::Version.to_a)
      assert_equal(
        [
          Semverve::Version::MAJOR,
          Semverve::Version::MINOR,
          Semverve::Version::PATCH
        ],
        Semverve::Version.to_a
      )
    end

    def test_to_s
      assert_instance_of(String, Semverve::Version.to_s)
      assert_match(/\d+\.\d+.\d+/, Semverve::Version.to_s)
    end

    def test_major
      assert_instance_of(Integer, Semverve::Version::MAJOR)
    end

    def test_minor
      assert_instance_of(Integer, Semverve::Version::MINOR)
    end

    def test_patch
      assert_instance_of(Integer, Semverve::Version::PATCH)
    end

    def test_gemfile_lock_should_contain_the_current_version
      refute_empty(
        File.readlines(
          File.join(__dir__, "..", "..", "Gemfile.lock")
        ).grep(GEMFILE_VERSION_REGEX)
      )
    end
  end
end
