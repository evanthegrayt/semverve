# frozen_string_literal: true

require_relative "lib/version_inc/task"
require "bundler/gem_tasks"
require "rdoc/task"
require "rake/testtask"
require "tmpdir"

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

VersionInc::Task.new do |t|
  t.bundle_lock = true
end

desc "Run Standard Ruby"
task :standard do
  ENV["RUBOCOP_CACHE_ROOT"] ||= File.join(File.realpath(Dir.tmpdir), "rubocop_cache")
  sh "bundle exec standardrb"
end

task default: :test
