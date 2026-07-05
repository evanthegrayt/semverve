# semverve

Rake tasks for reading, generating, and incrementing Ruby gem version files.

## Installation

Add the gem to your Gemfile:

```ruby
gem "semverve"
```

Then add this to your Rakefile:

```ruby
require "semverve/task"
```

This defines:

```text
rake semverve:current
rake semverve:increment:patch
rake semverve:increment:minor
rake semverve:increment:major
rake semverve:generate
```

## Configuration

By default, Semverve reads the single `.gemspec` in the project root, uses
`spec.name` as the gem name, and manages `lib/<gem_name>/version.rb`.

Override anything unusual in your Rakefile:

```ruby
require "semverve/task"

Semverve.configure do |config|
  config.format = :module
  config.bundle_lock = true
  config.version_file = "lib/standup_md/version.rb"
  config.module_name = "StandupMD"
end
```

Explicit task setup is also supported:

```ruby
Semverve::Task.new do |config|
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
rake semverve:generate
```

Generate a specific version or format:

```sh
rake semverve:generate VERSION=1.0.0 FORMAT=simple
```

Generation fails if the target file already exists. To replace it:

```sh
rake semverve:generate FORCE=true
```

## Incrementing

```sh
rake semverve:increment:patch
rake semverve:increment:minor
rake semverve:increment:major
```

Patch increments only patch. Minor increments minor and resets patch to `0`.
Major increments major and resets minor and patch to `0`.

Set `config.bundle_lock = true` to run `bundle lock` after increments.
