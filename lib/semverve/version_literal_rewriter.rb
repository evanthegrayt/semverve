# frozen_string_literal: true

require_relative "error"

module Semverve
  ##
  # Rewrites a named capture inside the first match for a safe version literal.
  class VersionLiteralRewriter
    ##
    # Initializes a literal rewriter.
    #
    # @param [Regexp] pattern
    # @param [String, #to_s] replacement
    # @param [Symbol, String] capture
    #
    # @return [Semverve::VersionLiteralRewriter]
    def initialize(pattern:, replacement:, capture: :version)
      @pattern = pattern
      @replacement = replacement.to_s
      @capture_name = capture.to_s
      @capture_key = capture.to_sym

      validate_capture
    end

    ##
    # Rewrites the configured capture in +text+.
    #
    # @param [String] text
    #
    # @return [String]
    def rewrite(text)
      text.sub(pattern) do |matched_text|
        match = Regexp.last_match
        capture_start = match.begin(capture_key) - match.begin(0)
        capture_end = match.end(capture_key) - match.begin(0)

        "#{matched_text[0...capture_start]}#{replacement}#{matched_text[capture_end..]}"
      end
    end

    private

    ##
    # Safe literal pattern.
    #
    # @return [Regexp]
    attr_reader :pattern

    ##
    # Replacement text.
    #
    # @return [String]
    attr_reader :replacement

    ##
    # Named capture as a string.
    #
    # @return [String]
    attr_reader :capture_name

    ##
    # Named capture as a symbol.
    #
    # @return [Symbol]
    attr_reader :capture_key

    ##
    # Validates that the pattern can be rewritten safely.
    #
    # @return [void]
    def validate_capture
      return if pattern.named_captures.key?(capture_name)

      raise Error, "version literal pattern must include a named capture called #{capture_name}."
    end
  end
end
