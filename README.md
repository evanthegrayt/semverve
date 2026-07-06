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
rake semverve:set VERSION=1.2.3
rake semverve:sync
rake semverve:sync:fix
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
  config.version_file = "lib/my_gem/version.rb"
  config.module_name = "MyGem"
  config.version_reference_files.append("doc/**/*.md", "lib/**/*.rb")
  config.version_reference_mode = :non_current
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
module MyGem
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

Successful increments print the version change:

```text
Updating to version 2.0.2 (was 2.0.1)
```

Set `config.bundle_lock = true` to run `bundle lock` after increments.

## Setting

Set an exact version without incrementing:

```sh
rake semverve:set VERSION=1.2.3
```

Successful updates print the version change:

```text
Updating to version 1.2.3 (was 1.2.2)
```

Setting the current version again does not rewrite the version file:

```text
Version is already 1.2.3
```

Setting a lower version prints a warning but still updates the file:

```text
Warning: updating to version 1.9.9, which is lower than the current version 2.0.1.
Updating to version 1.9.9 (was 2.0.1)
```

Set `config.bundle_lock = true` to run `bundle lock` after successful version
changes.

## Syncing version references

Check README files for references to older versions:

```sh
rake semverve:sync
```

Findings are printed in a parseable format and the task exits non-zero:

```text
README.md:12:24: version reference 1.2.2 -> 1.2.3
```

Replace stale references with the current version:

```sh
rake semverve:sync:fix
```

By default, Semverve scans README files throughout the repo. Add docs or Ruby
comments without replacing the defaults:

```ruby
Semverve.configure do |config|
  config.version_reference_files.append("doc/**/*.md", "lib/**/*.rb")
end
```

Replace the defaults entirely:

```ruby
Semverve.configure do |config|
  config.version_reference_files = Rake::FileList["guides/**/*.md"]
end
```

Ruby files are scanned only in comments. Text files with `.md`, `.markdown`,
`.txt`, `.rdoc`, and `.adoc` extensions are scanned as full text.

The default `:older` mode flags only semantic versions lower than the current
version. Use `:non_current` to flag any semantic version that does not match:

```ruby
Semverve.configure do |config|
  config.version_reference_mode = :non_current
end
```

Ignore an intentional reference with `semverve:ignore-version-reference` on the
same line or the preceding nonblank line.
