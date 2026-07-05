# frozen_string_literal: true

require_relative "formats/module_constants"
require_relative "formats/simple_string"

module Semverve
  module Formats
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
