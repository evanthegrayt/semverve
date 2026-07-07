# frozen_string_literal: true

module Semverve
  ##
  # Module that contains all gem version information. Follows semantic
  # versioning. Read: https://semver.org/
  module Version
    ##
    # Major version.
    #
    # @return [Integer]
    MAJOR = 0

    ##
    # Minor version.
    #
    # @return [Integer]
    MINOR = 2

    ##
    # Patch version.
    #
    # @return [Integer]
    PATCH = 0

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
  # The version, as a string.
  #
  # @return [String]
  VERSION = Version.to_s
end
