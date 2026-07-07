# frozen_string_literal: true

require_relative "error"
require_relative "version_checks"

module Semverve
  ##
  # Framework-specific configuration adapters.
  module Adapters
    class << self
      ##
      # Registers a framework adapter.
      #
      # @param [#name, #defaults, #checks] adapter
      #
      # @return [#name, #defaults, #checks]
      def register(adapter)
        adapters[adapter.name] = adapter
      end

      ##
      # Returns an adapter by name.
      #
      # @param [Symbol, String] name
      #
      # @return [#name, #defaults, #checks]
      def fetch(name)
        normalized_name = normalize_name(name)
        adapter = adapters[normalized_name]
        return adapter if adapter

        raise Error, unknown_adapter_message(name)
      end

      ##
      # Defaults for the configured adapter.
      #
      # @param [Symbol, String, nil] name
      # @param [Semverve::Configuration] configuration
      #
      # @return [Hash]
      def defaults_for(name, configuration)
        return {} unless name

        fetch(name).defaults(configuration)
      end

      ##
      # Checks supplied by all registered adapters.
      #
      # @return [Array<#name>]
      def checks
        adapters.values.flat_map(&:checks).each_with_object({}) do |check, checks|
          checks[check.name] = check
        end.values
      end

      ##
      # Checks supplied by the configured adapter.
      #
      # @param [Symbol, String, nil] name
      #
      # @return [Array<#name>]
      def checks_for(name)
        return [] unless name

        fetch(name).checks
      end

      ##
      # Whether package names should be inferred for the configured adapter.
      #
      # @param [Symbol, String, nil] name
      #
      # @return [Boolean]
      def infer_package_name?(name)
        return true unless name

        fetch(name).infer_package_name?
      end

      ##
      # Registered adapter names.
      #
      # @return [Array<Symbol>]
      def names
        adapters.keys
      end

      private

      ##
      # Adapter registry.
      #
      # @return [Hash<Symbol, #name>]
      def adapters
        @adapters ||= {}
      end

      ##
      # Normalizes an adapter name.
      #
      # @param [Object] name
      #
      # @return [Symbol, Object]
      def normalize_name(name)
        name.respond_to?(:to_sym) ? name.to_sym : name
      end

      ##
      # Error message for invalid adapters.
      #
      # @param [Object] name
      #
      # @return [String]
      def unknown_adapter_message(name)
        adapter_names = names.map(&:inspect)
        valid_adapters = "#{adapter_names[0...-1].join(", ")}, or #{adapter_names.last}"
        "Unknown adapter #{name.inspect}. Use #{valid_adapters}."
      end
    end

    ##
    # Shared adapter helpers.
    class Base
      ##
      # Framework-specific checks.
      #
      # @return [Array<#name>]
      def checks
        []
      end

      ##
      # Whether Semverve should infer package names from version files or gemspecs.
      #
      # @return [Boolean]
      def infer_package_name?
        true
      end

      private

      ##
      # Module name fallback based on the project directory.
      #
      # @param [String] root
      #
      # @return [String]
      def project_module_name(root)
        camelize(File.basename(File.expand_path(root)))
      end

      ##
      # Converts a project directory into a Ruby module name.
      #
      # @param [String] value
      #
      # @return [String]
      def camelize(value)
        value.split(/[_-]/).map(&:capitalize).join
      end
    end

    ##
    # Rails application adapter.
    class Rails < Base
      ##
      # Adapter name.
      #
      # @return [Symbol]
      def name
        :rails
      end

      ##
      # Rails-specific Semverve defaults.
      #
      # @param [Semverve::Configuration] _configuration
      #
      # @return [Hash]
      def defaults(_configuration)
        root = rails_root || Dir.pwd

        {
          format: :simple,
          module_name: rails_module_name || project_module_name(root),
          root: root,
          version_checks: [:doc_references, :code_references, :rails_config_metadata],
          version_file: File.join("config", "version.rb")
        }
      end

      ##
      # Rails-specific checks.
      #
      # @return [Array<#name>]
      def checks
        [VersionChecks::RailsConfigMetadataCheck.new]
      end

      ##
      # Rails apps should not infer a package name from config/version.rb.
      #
      # @return [Boolean]
      def infer_package_name?
        false
      end

      private

      ##
      # Rails.root when Rails is available.
      #
      # @return [String, nil]
      def rails_root
        return unless rails_defined?
        return unless ::Rails.respond_to?(:root)
        return unless ::Rails.root

        ::Rails.root.to_s
      end

      ##
      # Application module name inferred from Rails.application.
      #
      # @return [String, nil]
      def rails_module_name
        return unless rails_defined?
        return unless ::Rails.respond_to?(:application)
        return unless ::Rails.application

        application_class = ::Rails.application.class
        return application_class.module_parent_name if application_class.respond_to?(:module_parent_name)

        class_name = application_class.name
        return unless class_name&.include?("::")

        class_name.split("::").first
      end

      ##
      # Whether Rails is loaded.
      #
      # @return [Boolean]
      def rails_defined?
        Object.const_defined?(:Rails)
      end
    end

    ##
    # Sinatra application adapter.
    class Sinatra < Base
      ##
      # Adapter name.
      #
      # @return [Symbol]
      def name
        :sinatra
      end

      ##
      # Sinatra-specific Semverve defaults.
      #
      # @param [Semverve::Configuration] _configuration
      #
      # @return [Hash]
      def defaults(_configuration)
        root = Dir.pwd

        {
          format: :simple,
          module_name: project_module_name(root),
          root: root,
          version_checks: [:doc_references, :code_references],
          version_file: File.join("config", "version.rb")
        }
      end

      ##
      # Sinatra apps should not infer a package name from config/version.rb.
      #
      # @return [Boolean]
      def infer_package_name?
        false
      end
    end
  end
end

Semverve::Adapters.register(Semverve::Adapters::Rails.new)
Semverve::Adapters.register(Semverve::Adapters::Sinatra.new)
