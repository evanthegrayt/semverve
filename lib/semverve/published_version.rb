# frozen_string_literal: true

require "json"
require "net/http"
require "timeout"
require "uri"

require_relative "error"

module Semverve
  ##
  # Checks whether the current gem version already exists on a
  # RubyGems-compatible host.
  class PublishedVersion
    class << self
      ##
      # Callable used to fetch RubyGems-compatible API responses.
      #
      # @return [#call]
      attr_writer :http_getter

      ##
      # Returns the HTTP response fetcher.
      #
      # @return [#call]
      def http_getter
        @http_getter ||= ->(uri) { Net::HTTP.get_response(uri) }
      end
    end

    ##
    # Initializes a published-version check.
    #
    # @param [Semverve::ResolvedConfiguration] configuration
    # @param [Semverve::SemanticVersion] current_version
    #
    # @return [Semverve::PublishedVersion]
    def initialize(configuration, current_version)
      @configuration = configuration
      @current_version = current_version
    end

    ##
    # Whether the current version already exists on the configured host.
    #
    # @return [Boolean]
    def published?
      versions.any? { |version| version.fetch("number", nil).to_s == current_version.to_s }
    end

    ##
    # Raises if the current version already exists.
    #
    # @return [void]
    def check
      if published?
        raise Error, "#{configuration.gem_name} #{current_version} already exists on #{configuration.rubygems_host}."
      end
    end

    private

    ##
    # Resolved Semverve configuration.
    #
    # @return [Semverve::ResolvedConfiguration]
    attr_reader :configuration

    ##
    # Current gem version.
    #
    # @return [Semverve::SemanticVersion]
    attr_reader :current_version

    ##
    # Published versions from the configured RubyGems-compatible host.
    #
    # @return [Array<Hash>]
    def versions
      response = self.class.http_getter.call(versions_uri)

      case response.code.to_i
      when 200
        parse_versions(response.body)
      when 404
        []
      else
        raise Error, "Could not check #{configuration.gem_name} on #{configuration.rubygems_host}: HTTP #{response.code}."
      end
    rescue JSON::ParserError => error
      raise Error, "Could not parse published versions for #{configuration.gem_name}: #{error.message}"
    rescue SystemCallError, Timeout::Error, SocketError, URI::Error => error
      raise Error, "Could not check #{configuration.gem_name} on #{configuration.rubygems_host}: #{error.message}"
    end

    ##
    # Endpoint for a gem's published versions.
    #
    # @return [URI::HTTP, URI::HTTPS]
    def versions_uri
      URI("#{configuration.rubygems_host.chomp("/")}/api/v1/versions/#{URI.encode_www_form_component(configuration.gem_name)}.json")
    end

    ##
    # Parsed version response.
    #
    # @param [String] body
    #
    # @return [Array<Hash>]
    def parse_versions(body)
      versions = JSON.parse(body)
      return versions if versions.is_a?(Array)

      raise Error, "Could not parse published versions for #{configuration.gem_name}: expected an array."
    end
  end
end
