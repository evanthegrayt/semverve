# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/version_inc/version"

module VersionInc
  class VersionTest < Test::Unit::TestCase
    GEMFILE_VERSION_REGEX = %r{^\s*version_inc\s+\(#{VersionInc::VERSION}\)}o

    def test_version_exists_and_follows_semantiv_versioning
      assert VersionInc::VERSION
      assert_match VersionInc::Version.to_s, VersionInc::VERSION
    end

    def test_to_a
      assert_instance_of(Array, VersionInc::Version.to_a)
      assert_equal(
        [
          VersionInc::Version::MAJOR,
          VersionInc::Version::MINOR,
          VersionInc::Version::PATCH
        ],
        VersionInc::Version.to_a
      )
    end

    def test_to_h
      assert_instance_of(Hash, VersionInc::Version.to_h)
      assert_equal(
        {
          major: VersionInc::Version::MAJOR,
          minor: VersionInc::Version::MINOR,
          patch: VersionInc::Version::PATCH
        },
        VersionInc::Version.to_h
      )
    end

    def test_to_s
      assert_instance_of(String, VersionInc::Version.to_s)
      assert_match(/\d+\.\d+.\d+/, VersionInc::Version.to_s)
    end

    def test_major
      assert_instance_of(Integer, VersionInc::Version::MAJOR)
    end

    def test_minor
      assert_instance_of(Integer, VersionInc::Version::MINOR)
    end

    def test_patch
      assert_instance_of(Integer, VersionInc::Version::PATCH)
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
