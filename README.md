# Semverve
Rake tasks for handling the tedium surrounding maintaining a version number in
your Ruby project, with gusto!

## About
Maintaining a gem version is not hard, but there are so many little pieces that
are easy to forget. How many times have you had changes where the code was
ready, the tests were green, the PR was merged, you go to push the gem, and you
realize you forgot to bump the version? Then comes the tiny follow-up PR that
forces you to waste CI minutes for a two-line change, you submit it, and...  oh,
no! You still have references to the old version number in your documentation!
Rinse and repeat until you finally remember all the things.

Semverve is meant to make that tedium boring in the best way. It provides a
small set of Rake tasks for reading the current version, generating a version
file, incrementing patch/minor/major versions, setting an exact version, and
checking the places where version numbers tend to drift, like `.gemspec` files and
documentation.

In a nutshell, `rake semverve:increment:(patch|minor|major)` updates
your configured `version.rb` file, and `rake semverve:check` checks whether the
surrounding project still agrees with that version. It can catch stale README
references, safe code literals, `.gemspec` drift, and a stale `Gemfile.lock`
entry. If you want Semverve to do the mechanical cleanup, the matching `*:fix`
tasks can update safe references and run `bundle lock` for generated lockfile
drift. Specific findings can be skipped with magic comments, similar to RuboCop
and RDoc.

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
  config.version_code_reference_pattern =
    /^\s*(?:(?:[A-Z]\w*::)*(?:[A-Z]\w*VERSION[A-Z0-9_]*|VERSION)|(?:[a-z_]\w*|self)\.version)\s*=\s*(?<quote>["'])(?<version>\d+\.\d+\.\d+)\k<quote>/
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

## Publishing generated docs
Semverve also includes an optional GitHub Pages publishing task for generated
documentation. It builds docs on your current branch, opens the publishing
branch in a temporary Git worktree, copies the generated docs there, commits any
changes, and pushes the publishing branch.

Add this to your Rakefile:

```ruby
require "semverve/docs_publisher/task"

Semverve::DocsPublisher::Task.new
```

This defines:

```text
rake docs:publish
rake docs:publish:dry_run
```

The defaults are equivalent to:

```ruby
Semverve::DocsPublisher::Task.new do |task|
  task.root = Dir.pwd
  task.build_task = "rerdoc"
  task.source_dir = "docs"
  task.target_dir = "docs"
  task.branch = "gh-pages"
  task.remote = "origin"
  task.commit_message = "Update generated documentation"
  task.allow_dirty = false
  task.push = true
  task.output = $stdout
end
```

`docs:publish` requires a clean working tree by default. Set
`task.allow_dirty = true` only when you intentionally want to publish generated
documentation from uncommitted source changes.

## Rails apps
Rails applications do not need gem-style version files, but an application
version can still be useful for release notes, support/debug screens,
deployment metadata, or API output.

When Rails is loaded, Semverve's Railtie installs the same `semverve:*` Rake
tasks for `bin/rails`/`rails` automatically. To use Rails-style defaults, set
the Rails preset:

```ruby
Semverve.configure do |config|
  config.preset = :rails
end
```

The Rails preset uses `Rails.root`, stores the version in
`config/version.rb`, uses the `:simple` format, and infers the module name from
your Rails application module when possible.

Generate the file with:

```sh
bin/rails semverve:generate
```

If your app keeps the version somewhere else, override the path:

```ruby
Semverve.configure do |config|
  config.preset = :rails
  config.version_file = "config/releases/version.rb"
end
```

Rails support is only a preset and a Railtie; Semverve does not require a dummy
app, a Rails plugin layout, or a Rails dependency.

## Formats
The default `:module` format stores `MAJOR`, `MINOR`, and `PATCH` constants
under a `Version` module and exposes a top-level `VERSION` constant.

```ruby
module MyGem
  module Version
    MAJOR = 0
    MINOR = 1
    PATCH = 0

    module_function

    def to_a
      [MAJOR, MINOR, PATCH]
    end

    def to_s
      to_a.join(".")
    end
  end

  VERSION = Version.to_s
end
```

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

Set `config.bundle_lock = true` to run `bundle lock` after increments to update
your gem's version in `Gemfile.lock`.

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

This will also run `bundle lock` on success if you have `config.bundle_lock =
true` in your config.

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

The default pattern is Ruby-oriented. Semverve does not inspect file extensions
or parse other languages for code literals; non-Ruby files are scanned as plain
text with the same pattern. If a JavaScript, Python, or other source file uses a
different version-literal shape, configure a custom pattern before adding those
files.

Arbitrary string examples are ignored.

If your project has a different safe version-literal shape, provide your own
pattern:

```ruby
Semverve.configure do |config|
  config.version_code_reference_files.append("lib/**/*.rb")
  config.version_code_reference_pattern = /release ["'](?<version>\d+\.\d+\.\d+)["']/
end
```

With that pattern, this line:

```ruby
release "1.2.2"
```

matches the full `release "1.2.2"` text, but only `1.2.2` is captured as
`version`. If `rake semverve:fix:code` is updating references to `1.2.3`, the
line becomes:

```ruby
release "1.2.3"
```

The custom value must be a `Regexp` and must include a named capture called
`version`. Semverve replaces only that capture when running
`rake semverve:fix:code`, and the captured value still has to parse as a
semantic version.

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

## Reporting Bugs and Requesting Features
If you have an idea or find a bug, please [create an
issue](https://github.com/evanthegrayt/semverve/issues/new). Just make sure
the topic doesn't already exist. Better yet, you can always submit a Pull
Request.

## Support this project
I love knowing when people find my work useful. Any kind of support is very much
appreciated!

- ⭐️ Like the project? Star [the repository](https://github.com/evanthegrayt/semverve)!
- ❤️ Love the project? Follow me [on GitHub](https://github.com/evanthegrayt)!
- 💸 *Really* love it? Consider [buying me a tea](https://paypal.me/evanrgray)!
