# frozen_string_literal: true

require_relative "error"

module Semverve
  ##
  # Framework-specific default configuration adapters.
  module Presets
    ##
    # Returns defaults for a configured preset.
    #
    # @param [Symbol, String, nil] name
    # @param [Semverve::Configuration] configuration
    #
    # @return [Hash]
    def self.defaults_for(name, configuration)
      return {} unless name

      fetch(name).defaults(configuration)
    end

    ##
    # Returns a preset adapter.
    #
    # @param [Symbol, String] name
    #
    # @return [#name, #defaults]
    def self.fetch(name)
      case name.to_sym
      when :rails
        Rails.new
      else
        raise Error, "Unknown preset #{name.inspect}. Use :rails."
      end
    end

    ##
    # Rails application defaults.
    class Rails
      ##
      # Preset name.
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
          version_file: File.join("config", "version.rb")
        }
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
      # Module name fallback based on the project directory.
      #
      # @param [String] root
      #
      # @return [String]
      def project_module_name(root)
        camelize(File.basename(File.expand_path(root)))
      end

      ##
      # Whether Rails is loaded.
      #
      # @return [Boolean]
      def rails_defined?
        Object.const_defined?(:Rails)
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
  end
end
