# version_inc

Rake tasks for reading, generating, and incrementing Ruby gem version files.

## Installation

Add the gem to your Gemfile:

```ruby
gem "version_inc"
```

Then add this to your Rakefile:

```ruby
require "version_inc/task"
```

This defines:

```text
rake version_inc:current
rake version_inc:increment:patch
rake version_inc:increment:minor
rake version_inc:increment:major
rake version_inc:generate
```

## Configuration

By default, VersionInc reads the single `.gemspec` in the project root, uses
`spec.name` as the gem name, and manages `lib/<gem_name>/version.rb`.

Override anything unusual in your Rakefile:

```ruby
require "version_inc/task"

VersionInc.configure do |config|
  config.format = :module
  config.bundle_lock = true
  config.version_file = "lib/standup_md/version.rb"
  config.module_name = "StandupMD"
end
```

Explicit task setup is also supported:

```ruby
VersionInc::Task.new do |config|
  config.bundle_lock = true
end
```

## Formats

The default `:module` format stores `MAJOR`, `MINOR`, and `PATCH` constants
under a `Version` module and exposes a top-level `VERSION` constant.

The `:simple` format stores only:

```ruby
module StandupMD
  VERSION = "1.0.0"
end
```

## Generating

Generate the default module format:

```sh
rake version_inc:generate
```

Generate a specific version or format:

```sh
rake version_inc:generate VERSION=1.0.0 FORMAT=simple
```

Generation fails if the target file already exists. To replace it:

```sh
rake version_inc:generate FORCE=true
```

## Incrementing

```sh
rake version_inc:increment:patch
rake version_inc:increment:minor
rake version_inc:increment:major
```

Patch increments only patch. Minor increments minor and resets patch to `0`.
Major increments major and resets minor and patch to `0`.

Set `config.bundle_lock = true` to run `bundle lock` after increments.
