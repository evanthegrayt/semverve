# frozen_string_literal: true

module Semverve
  ##
  # Result of fixing one Semverve check surface.
  class FixResult
    ##
    # Files changed by the fix.
    #
    # @return [Array<String>]
    attr_reader :changed_files

    ##
    # Number of replacements made.
    #
    # @return [Integer]
    attr_reader :replacement_count

    ##
    # Whether the fix ran +bundle lock+.
    #
    # @return [Boolean]
    attr_reader :bundle_lock_ran

    ##
    # Initializes a fix result.
    #
    # @param [Array<String>] changed_files
    # @param [Integer] replacement_count
    # @param [Boolean] bundle_lock_ran
    #
    # @return [Semverve::FixResult]
    def initialize(changed_files:, replacement_count:, bundle_lock_ran: false)
      @changed_files = changed_files
      @replacement_count = replacement_count
      @bundle_lock_ran = bundle_lock_ran
    end
  end
end
