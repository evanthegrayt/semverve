# semverve

Rake tasks for reading, generating, and incrementing Ruby gem version files.

## About

Maintaining a gem version is not hard, but it is easy to forget. I have had
plenty of changes where the code was ready, the tests were green, the PR was
merged, and then I noticed that the version file, lockfile, or docs still said
the old thing. Then comes the tiny follow-up PR that exists only because I did
not remember to bump a number before merging.

Semverve is meant to make that tedium boring in the best way. It gives a gem a
small set of Rake tasks for reading the current version, generating a version
file, incrementing patch/minor/major versions, setting an exact version, and
checking the places where version numbers tend to drift.

In a nutshell, `rake semverve:increment:patch` updates your configured
`version.rb` file, and `rake semverve:check` checks whether the surrounding
project still agrees with that version. It can catch stale README references,
safe code literals, `.gemspec` drift, and a stale `Gemfile.lock` entry. If you
want Semverve to do the mechanical cleanup, the matching `*:fix` tasks can
update safe references and run `bundle lock` for generated lockfile drift.

The goal is not to replace your release process. It is to take care of the
small, forgettable version-maintenance chores around that process, so you do
not have to remember them at the worst possible moment.

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
rake semverve:check
rake semverve:fix
rake semverve:check:references
rake semverve:fix:references
rake semverve:check:code
rake semverve:fix:code
rake semverve:check:metadata
rake semverve:fix:metadata
```

## Configuration

By default, Semverve reads the single `.gemspec` in the project root, uses
`spec.name` as the gem name, and manages `lib/<gem_name>/version.rb`.

For a conventional gem, this may be all you need:

```ruby
require "semverve/task"
```

That automatically installs the `semverve:*` Rake tasks. If you want to make
the setup explicit, or if you want to change any defaults, configure Semverve
from your Rakefile:

```ruby
require "semverve/task"

Semverve.configure do |config|
  config.format = :module
  config.bundle_lock = true
  config.version_file = "lib/my_gem/version.rb"
  config.module_name = "MyGem"
  config.version_checks = [:doc_references, :code_references, :metadata]
  config.version_code_reference_files.append("lib/**/*.rb")
  config.version_doc_reference_files.append("doc/**/*.md")
  config.version_reference_mode = :non_current
end
```

The core defaults are equivalent to:

```ruby
Semverve.configure do |config|
  config.format = :module
  config.bundle_lock = false
  config.root = Dir.pwd
  config.version_checks = [:doc_references, :code_references, :metadata]
  config.version_reference_mode = :older
  config.version_code_reference_files = Rake::FileList[]
  config.version_doc_reference_files = Rake::FileList["README*", "**/README*"].exclude(
    ".git/**/*",
    "coverage/**/*",
    "tmp/**/*",
    "vendor/**/*"
  )
end
```

The empty `version_code_reference_files` default only applies to arbitrary code
literal scanning. `rake semverve:check` still checks the resolved `.gemspec`
version and matching `Gemfile.lock` entry through its default metadata check.

The gem name, module name, and version-file path are inferred by default:

```ruby
config.gem_name     # spec.name from the single .gemspec
config.module_name  # camelized gem name, such as "MyGem"
config.version_file # lib/<gem_name>/version.rb
```

Override them when your project does something unusual:

```ruby
Semverve.configure do |config|
  config.gem_name = "my-gem"
  config.module_name = "MyGem"
  config.version_file = "lib/my_gem/version.rb"
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

## Checking version references, code, and metadata

Run every version check with:

```sh
rake semverve:check
```

By default, this checks:

- README version references, plus any configured docs or comment files
- configured code files for safe version literals
- the gemspec version and `Gemfile.lock` entry

Findings are printed in parseable formats and the task exits non-zero:

```text
README.md:12:24: version reference 1.2.2 -> 1.2.3
lib/my_gem/constants.rb:1:16: code version literal 1.2.2 -> 1.2.3
my_gem.gemspec:3:18: gemspec version 1.2.2 -> 1.2.3
Gemfile.lock:4:13: locked version 1.2.2 -> 1.2.3
```

Run every available fix:

```sh
rake semverve:fix
```

Choose which surfaces the umbrella `check` and `fix` tasks run with
`config.version_checks`:

```ruby
Semverve.configure do |config|
  config.version_checks = [:doc_references, :metadata]
end
```

The allowed values are `:doc_references`, `:code_references`, and `:metadata`.

Use focused tasks when you want only one surface:

```sh
rake semverve:check:references
rake semverve:fix:references
rake semverve:check:code
rake semverve:fix:code
rake semverve:check:metadata
rake semverve:fix:metadata
```

`semverve:fix:metadata` rewrites literal gemspec versions when safe and
runs `bundle lock` for `Gemfile.lock` drift.

### Version references

Version references are prose-like references to versions. These are usually in
README files, docs, guides, or comments. By default, Semverve scans README files
throughout the repo:

```ruby
Semverve.configure do |config|
  config.version_doc_reference_files = Rake::FileList["README*", "**/README*"].exclude(
    ".git/**/*",
    "coverage/**/*",
    "tmp/**/*",
    "vendor/**/*"
  )
end
```

Add docs or Ruby comments without replacing the README defaults:

```ruby
Semverve.configure do |config|
  config.version_doc_reference_files.append("doc/**/*.md", "lib/**/*.rb")
end
```

Replace the defaults entirely:

```ruby
Semverve.configure do |config|
  config.version_doc_reference_files = Rake::FileList["guides/**/*.md"]
end
```

Ruby files are scanned only in comments. Text files with `.md`, `.markdown`,
`.txt`, `.rdoc`, and `.adoc` extensions are scanned as full text.

The default reference mode is `:older`, which flags only semantic versions lower
than the current version:

```ruby
Semverve.configure do |config|
  config.version_reference_mode = :older
end
```

Use `:non_current` when every reference should match the current version:

```ruby
Semverve.configure do |config|
  config.version_reference_mode = :non_current
end
```

Ignore an intentional reference with `semverve:ignore-version-reference` on the
same line or the preceding nonblank line.

```markdown
This migration note intentionally mentions 1.0.0. <!-- semverve:ignore-version-reference -->
```

### Code version literals

Code scanning is opt-in to avoid false positives. This is for arbitrary project
code, not gem metadata. The default is:

```ruby
Semverve.configure do |config|
  config.version_code_reference_files = Rake::FileList[]
end
```

Append files when you want Semverve to check safe code literals:

```ruby
Semverve.configure do |config|
  config.version_code_reference_files.append("lib/**/*.rb")
end
```

Or replace the list entirely:

```ruby
Semverve.configure do |config|
  config.version_code_reference_files = Rake::FileList["lib/**/*.rb", "*.gemspec"]
end
```

Ruby code checks only obvious version assignments/constants, such as:

```ruby
APP_VERSION = "1.2.2"
spec.version = "1.2.2"
```

Arbitrary string examples are ignored.

### Metadata

Metadata checks are part of `rake semverve:check` by default. They compare the
current version file against:

- the resolved `.gemspec` version
- the matching `Gemfile.lock` entry, when a lockfile exists

Metadata always requires an exact match, regardless of
`config.version_reference_mode`.

No file-list configuration is needed for these checks. Semverve resolves the
gemspec from the project root and reads `Gemfile.lock` when one exists.

Dynamic gemspec versions work as expected:

```ruby
require_relative "lib/my_gem/version"

Gem::Specification.new do |spec|
  spec.name = "my_gem"
  spec.version = MyGem::VERSION
end
```

Literal gemspec versions can be fixed automatically:

```ruby
Gem::Specification.new do |spec|
  spec.name = "my_gem"
  spec.version = "1.2.2"
end
```

`rake semverve:fix:metadata` updates safe literal gemspec assignments and
runs `bundle lock` when the lockfile has drifted.
