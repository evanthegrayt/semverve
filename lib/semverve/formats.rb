# frozen_string_literal: true

require_relative "formats/module_constants"
require_relative "formats/simple_string"

module Semverve
  ##
  # Format handlers for parsing, replacing, and generating version files.
  module Formats
    ##
    # Returns the handler for a configured version-file format.
    #
    # @param [Symbol, String] name
    #
    # @return [Semverve::Formats::ModuleConstants, Semverve::Formats::SimpleString]
    def self.fetch(name)
      case name.to_sym
      when :module
        ModuleConstants.new
      when :simple
        SimpleString.new
      else
        raise Error, "Unknown version format #{name.inspect}. Use :module or :simple."
      end
    end
  end
end
