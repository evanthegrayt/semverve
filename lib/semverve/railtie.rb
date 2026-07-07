# frozen_string_literal: true

require_relative "../semverve"

module Semverve
  ##
  # Rails integration for installing Semverve's Rake tasks.
  class Railtie < ::Rails::Railtie
    rake_tasks do
      Semverve.configuration.adapter = :rails unless Semverve.configuration.adapter

      require_relative "task"
      Semverve::Task.install
    end
  end
end
