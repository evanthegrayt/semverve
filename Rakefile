# frozen_string_literal: true

require_relative "lib/semverve/task"
require "bundler/gem_tasks"
require "rdoc/task"
require "rake/testtask"

Rake::TestTask.new do |t|
  t.libs = ["lib"]
  t.warning = true
  t.verbose = true
  t.test_files = FileList["test/**/*_test.rb"]
end

RDoc::Task.new do |rdoc|
  rdoc.main = "README.md"
  rdoc.rdoc_dir = "docs"
  rdoc.rdoc_files.include("README.md", "lib/**/*.rb")
end

Semverve::Task.new do |config|
  config.task_namespace = :version
  config.bundle_lock = true
  config.version_code_reference_files.append(
    "lib/**/*.rb",
    "semverve.gemspec",
    "Rakefile"
  )
  config.version_reference_ignores = {
    "README.md" => {380 => "0.0.0"}
  }
end

standardrb = ->(*args) do
  sh(["bundle", "exec", "standardrb", *args].join(" "))
end

desc "Run Standard Ruby"
task :standard do
  standardrb.call
end

namespace :standard do
  desc "Fix Standard Ruby offenses"
  task :fix do
    standardrb.call("--fix")
  end
end

task default: [:test, "version:check"]
