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

Semverve::Task.new do |t|
  t.bundle_lock = true
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

task default: :test
