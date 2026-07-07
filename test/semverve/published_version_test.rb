# frozen_string_literal: true

require "json"

require_relative "../test_helper"
require_relative "../../lib/semverve/published_version"
require_relative "../../lib/semverve/semantic_version"

module Semverve
  class PublishedVersionTest < Test::Unit::TestCase
    Configuration = Struct.new(:gem_name, :rubygems_host, keyword_init: true)
    Response = Struct.new(:code, :body, keyword_init: true)

    def test_reports_unpublished_version
      with_stubbed_response(200, [{"number" => "1.2.2"}]) do
        refute published_version("1.2.3").published?
      end
    end

    def test_reports_published_version
      with_stubbed_response(200, [{"number" => "1.2.3"}, {"number" => "1.2.2"}]) do
        assert published_version("1.2.3").published?
      end
    end

    def test_missing_gem_is_unpublished
      with_stubbed_response(404, {"error" => "This rubygem could not be found."}) do
        refute published_version("1.2.3").published?
      end
    end

    def test_check_fails_when_version_is_already_published
      with_stubbed_response(200, [{"number" => "1.2.3"}]) do
        error = assert_raise(Error) { published_version("1.2.3").check }

        assert_equal "my_gem 1.2.3 already exists on https://rubygems.org.", error.message
      end
    end

    def test_check_uses_encoded_gem_name_and_configured_host
      with_stubbed_response(200, []) do |requests|
        published_version("1.2.3", gem_name: "my gem", host: "https://gems.example.test/").check

        assert_equal "/api/v1/versions/my+gem.json", requests.first.path
        assert_equal "gems.example.test", requests.first.host
      end
    end

    def test_malformed_json_fails_loudly
      with_stubbed_raw_response(200, "not json") do
        error = assert_raise(Error) { published_version("1.2.3").published? }

        assert_match(/Could not parse published versions for my_gem/, error.message)
      end
    end

    def test_unexpected_json_shape_fails_loudly
      with_stubbed_response(200, {"versions" => []}) do
        error = assert_raise(Error) { published_version("1.2.3").published? }

        assert_equal "Could not parse published versions for my_gem: expected an array.", error.message
      end
    end

    def test_http_error_fails_loudly
      with_stubbed_response(500, {"error" => "Internal server error"}) do
        error = assert_raise(Error) { published_version("1.2.3").published? }

        assert_equal "Could not check my_gem on https://rubygems.org: HTTP 500.", error.message
      end
    end

    def test_network_error_fails_loudly
      with_stubbed_network_error(SocketError.new("host down")) do
        error = assert_raise(Error) { published_version("1.2.3").published? }

        assert_equal "Could not check my_gem on https://rubygems.org: host down", error.message
      end
    end

    private

    def published_version(version, gem_name: "my_gem", host: "https://rubygems.org")
      PublishedVersion.new(
        Configuration.new(gem_name: gem_name, rubygems_host: host),
        SemanticVersion.parse(version)
      )
    end

    def with_stubbed_response(code, body)
      with_stubbed_raw_response(code, JSON.generate(body)) { |requests| yield requests }
    end

    def with_stubbed_raw_response(code, body)
      response = Response.new(code: code.to_s, body: body)
      requests = []
      original = PublishedVersion.http_getter
      PublishedVersion.http_getter = ->(uri) do
        requests << uri
        response
      end

      yield requests
    ensure
      PublishedVersion.http_getter = original
    end

    def with_stubbed_network_error(error)
      original = PublishedVersion.http_getter
      PublishedVersion.http_getter = ->(_uri) do
        raise error
      end

      yield
    ensure
      PublishedVersion.http_getter = original
    end
  end
end
