# frozen_string_literal: true

require "simplecov"

SimpleCov.start { add_filter %r{^/test/} }

require "test/unit"
require_relative "../lib/version_inc"

module TestHelper
end
