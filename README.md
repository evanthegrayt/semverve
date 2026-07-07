# Semverve
[![Build Status](https://img.shields.io/endpoint.svg?url=https%3A%2F%2Factions-badge.atrox.dev%2Fevanthegrayt%2Fsemverve%2Fbadge%3Fref%3Dmaster&style=flat)](https://actions-badge.atrox.dev/evanthegrayt/semverve/goto?ref=master)
[![Language: Ruby](https://img.shields.io/static/v1?label=language&message=Ruby&color=CC342D&style=flat&logo=ruby&logoColor=CC342D)](https://www.ruby-lang.org/)
[![Gem Version](https://img.shields.io/gem/v/semverve.svg)](https://rubygems.org/gems/semverve)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

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

You can view the documentation
[here](https://evanthegrayt.github.io/semverve/).

If you are upgrading across breaking changes, see [UPGRADING.md](UPGRADING.md).

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
rake 'semverve:set[1.2.3]'
rake semverve:check
rake semverve:fix
rake semverve:check:references
rake semverve:fix:references
rake semverve:check:code
rake semverve:fix:code
rake semverve:check:package_metadata
rake semverve:fix:package_metadata
rake semverve:check:rails_config_metadata
rake semverve:fix:rails_config_metadata
rake semverve:check:rubygems
rake semverve:check:release
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
  config.version_checks = [:doc_references, :code_references, :package_metadata]
  config.release_checks = [:rubygems]
  config.rubygems_host = "https://rubygems.org"
  config.version_code_reference_files.append("lib/**/*.rb")
  config.version_doc_reference_files.append("doc/**/*.md")
  config.version_match_mode = :non_current
end
```

The core defaults are equivalent to:

```ruby
Semverve.configure do |config|
  config.adapter = nil
  config.format = :module
  config.bundle_lock = false
  config.root = Dir.pwd
  config.version_checks = [:doc_references, :code_references, :package_metadata]
  config.release_checks = []
  config.rubygems_host = "https://rubygems.org"
  config.version_match_mode = :older
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
version and matching `Gemfile.lock` entry through its default package metadata
check.
Release checks are empty by default because they may make network requests and
are intended for release pipelines rather than every local or pull-request run.

Semverve tasks use Rake task arguments for values:

```sh
rake 'semverve:set[1.2.3]'
rake 'semverve:generate[1.0.0,simple]'
rake 'semverve:generate[simple]'
rake 'semverve:generate[force]'
```

Quote task invocations that include square brackets. Shells such as zsh may
otherwise treat brackets as glob patterns before Rake sees them. Flag syntax
such as `rake semverve:set --version 1.2.3` is not used because `--version` is
already a Rake option; Semverve stays within Rake's native argument syntax
instead.

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

## Framework adapters
Framework adapters provide app-oriented defaults without requiring a gemspec or
package identity. `config.adapter` is the preferred API; `config.preset` remains
supported as a backward-compatible alias.

## Rails apps
Rails applications do not need gem-style version files, but an application
version can still be useful for release notes, support/debug screens,
deployment metadata, or API output.

When Rails is loaded, Semverve's Railtie installs the same `semverve:*` Rake
tasks for `bin/rails`/`rails` automatically. To use Rails-style defaults, set
the Rails adapter:

```ruby
Semverve.configure do |config|
  config.adapter = :rails
end
```

`config.preset = :rails` is still accepted for existing setups.

The Rails adapter uses `Rails.root`, stores the version in
`config/version.rb`, uses the `:simple` format, and infers the module name from
your Rails application module when possible. Its default checks are app-oriented:
documentation references, configured code literals, and optional Rails config
metadata. It does not run package metadata checks unless you opt in.

Generate the file with:

```sh
bin/rails semverve:generate
```

If your app keeps the version somewhere else, override the path:

```ruby
Semverve.configure do |config|
  config.adapter = :rails
  config.version_file = "config/releases/version.rb"
end
```

Rails support is only an adapter and a Railtie; Semverve does not require a dummy
app, a Rails plugin layout, or a Rails dependency.

Rails config metadata is optional. When present, Semverve checks safe literals
in `config/application.rb`, `config/environments/*.rb`, and
`config/initializers/**/*.rb`:

```ruby
config.x.version = "1.2.2"
Rails.application.config.x.version = "1.2.2"
```

Dynamic assignments are treated as self-managed and left alone:

```ruby
config.x.version = Storefront::VERSION
```

Rails engines or apps that publish gems can opt into package metadata checks by
setting `config.gem_name` and including `:package_metadata` in
`config.version_checks`. Deployment and container metadata, such as Docker,
Kamal, and Helm, are intentionally left for future adapter support.

## Sinatra apps
Sinatra applications can use the Sinatra adapter for app-style defaults:

```ruby
Semverve.configure do |config|
  config.adapter = :sinatra
end
```

The Sinatra adapter stores the version in `config/version.rb`, uses the
`:simple` format, infers the module name from the project directory, and checks
documentation references plus configured code literals by default. It does not
infer a package name from `config/version.rb` and does not run package metadata
checks unless you opt in.

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
rake 'semverve:generate[1.0.0,simple]'
rake 'semverve:generate[simple]'
```

Generation fails if the target file already exists. To replace it:

```sh
rake 'semverve:generate[force]'
```

`semverve:generate` accepts optional tokens for version, format, and force.
Token order does not matter: semantic versions set the generated version,
`module` or `simple` sets the format, and `force` overwrites an existing version
file.

```sh
rake 'semverve:generate[1.0.0,force]'
rake 'semverve:generate[simple,force]'
rake 'semverve:generate[1.0.0,simple,force]'
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
rake 'semverve:set[1.2.3]'
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

This task is designed for normal CI. It uses local project files, prints
parseable findings, and exits non-zero when it finds drift.

By default, gem/package projects check:

- README version references, plus any configured docs or comment files
- configured code files for safe version literals
- the gemspec version and `Gemfile.lock` entry

Rails adapter projects instead check README references, configured code literals,
and optional Rails config metadata.

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
  config.version_checks = [:doc_references, :package_metadata]
end
```

The allowed values come from Semverve's check registry. Built-in checks are
`:doc_references`, `:code_references`, and `:package_metadata`; framework
adapters can add their own checks, such as Rails' `:rails_config_metadata`.

Use focused tasks when you want only one surface:

```sh
rake semverve:check:references
rake semverve:fix:references
rake semverve:check:code
rake semverve:fix:code
rake semverve:check:package_metadata
rake semverve:fix:package_metadata
rake semverve:check:rails_config_metadata
rake semverve:fix:rails_config_metadata
```

`semverve:fix:package_metadata` rewrites literal gemspec versions when safe and
runs `bundle lock` for `Gemfile.lock` drift. `semverve:fix:rails_config_metadata`
rewrites safe Rails config version literals.

Pass a semantic version when you want to check or fix only that exact version in
doc references and code literals:

```sh
rake 'semverve:check[1.2.2]'
rake 'semverve:fix:references[1.2.2]'
```

Package metadata and adapter-owned metadata checks still compare metadata to the
current version. If you target the current version, check tasks list
reference/code matches but fix tasks are no-ops because the text is already
current.

## Extension API
Semverve exposes small public objects for framework adapters and version checks.
These APIs are intentionally local registration APIs; Semverve does not yet
autoload third-party adapter gems.

Register a framework adapter with `Semverve::Adapters.register`. An adapter
must expose `name`, `defaults(configuration)`, and `checks`. It can also expose
`infer_package_name?` to control whether app-style version files should be
treated as package names.

Register a check with `Semverve::VersionChecks.register`, or return adapter-owned
checks from an adapter's `checks` method. A check object should expose:

- `name` and `task_name`
- `check_description`, `fix_description`, `finding_label`, and `fix_label`
- `clean_message`, `targetable?`, and `exact_target_fix_noop_notice?`
- `findings(configuration, current_version, include_ignored:, target_version:)`
- `fix(configuration, current_version, target_version:)`

Checks should return `Semverve::Finding` objects from `findings` and a
`Semverve::FixResult` from `fix`. `Semverve::VersionMatchPolicy` and
`Semverve::VersionLiteralRewriter` are available for checks that need Semverve's
standard stale-version matching or named-capture literal rewriting.

For example:

```ruby
class MyConfigVersionCheck < Semverve::VersionChecks::Check
  def name = :my_config_metadata
  def task_name = :my_config_metadata
  def check_description = "Check app config metadata for version mismatches"
  def fix_description = "Fix safe app config metadata version mismatches"
  def finding_label = "app config version"
  def clean_message = "App config metadata is current."

  def findings(configuration, current_version, include_ignored: false, target_version: nil)
    []
  end

  def fix(configuration, current_version, target_version: nil)
    Semverve::FixResult.new(changed_files: [], replacement_count: 0)
  end
end
```

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

The default version match mode is `:older`, which flags only semantic versions
lower than the current version in doc references and code literals:

```ruby
Semverve.configure do |config|
  config.version_match_mode = :older
end
```

Use `:non_current` when every doc reference and code literal should match the
current version:

```ruby
Semverve.configure do |config|
  config.version_match_mode = :non_current
end
```

Ignore an intentional reference with `semverve:ignore-version-reference` on the
same line or the preceding nonblank line.

```markdown
This migration note intentionally mentions 1.0.0. <!-- semverve:ignore-version-reference -->
```

Audit ignored references by setting `SEMVERVE_REPORT_IGNORED=true` when running
check tasks:

```sh
SEMVERVE_REPORT_IGNORED=true rake semverve:check
SEMVERVE_REPORT_IGNORED=true rake 'semverve:check[1.2.2]'
```

### Code version literals
Code scanning is opt-in to avoid false positives. This is for arbitrary project
code, not package metadata. The default is:

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

Ignore an intentional code literal with `semverve:ignore-version-reference` on
the same line or the preceding nonblank line.

Set `SEMVERVE_REPORT_IGNORED=true` with `semverve:check` or
`semverve:check:code` to report ignored stale literals without changing
`semverve:fix` behavior.

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

### Package metadata
Package metadata checks are part of `rake semverve:check` by default for
gem/package projects. They compare the current version file against:

- the resolved `.gemspec` version
- the matching `Gemfile.lock` entry, when a lockfile exists

Package metadata always requires an exact match, regardless of
`config.version_match_mode`.

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

`rake semverve:fix:package_metadata` updates safe literal gemspec assignments and
runs `bundle lock` when the lockfile has drifted.

### Rails config metadata
Rails config metadata checks are part of `rake semverve:check` when the Rails
adapter is active. They scan `config/application.rb`,
`config/environments/*.rb`, and `config/initializers/**/*.rb` for optional Rails
config literals:

```ruby
config.x.version = "1.2.2"
Rails.application.config.x.version = "1.2.2"
```

These checks always require an exact match with the current Semverve version.
`rake semverve:fix:rails_config_metadata` rewrites only those safe string
literals. Dynamic assignments, including `config.x.version = Storefront::VERSION`,
are considered self-managed and ignored.

## Checking release readiness
Release checks are separate from `rake semverve:check`. They are useful in CI,
but they are meant for release workflows, tag builds, or pre-publish jobs rather
than every pull request.

Enable the RubyGems published-version check:

```ruby
Semverve.configure do |config|
  config.release_checks = [:rubygems]
end
```

Then run:

```sh
rake semverve:check:release
```

With `:rubygems` enabled, `semverve:check:release` asks the configured
RubyGems-compatible host whether the current version already exists. If it does,
the task exits non-zero with a message like:

```text
my_gem 1.2.3 already exists on https://rubygems.org.
```

If all configured release checks pass, it prints:

```text
Release checks passed.
```

You can also run the RubyGems check directly without changing
`config.release_checks`:

```sh
rake semverve:check:rubygems
```

When the current version is not published, the focused task prints:

```text
my_gem 1.2.3 is not published on https://rubygems.org.
```

Use `config.rubygems_host` for a private RubyGems-compatible server:

```ruby
Semverve.configure do |config|
  config.release_checks = [:rubygems]
  config.rubygems_host = "https://gems.example.com"
end
```

The published-version check treats a missing gem as unpublished. It fails closed
on registry errors, malformed responses, and network failures because release
pipelines should not silently publish after an inconclusive preflight.

For ordinary CI, keep using the local checks:

```sh
bundle exec rake test semverve:check
```

For release CI, run the release check before building or pushing:

```sh
bundle exec rake semverve:check:release build
```

## Vim
While there's no official vim support (yet), you can add the following to
`~/.vim/plugin/semverve.vim`.

```vim
command! -bang SemverveAudit call <SID>semverve_audit(<bang>0)
function! s:semverve_audit(report_ignored) abort
  let l:old_efm = &errorformat
  try
    let &errorformat = '%f:%l:%c:%m'
    let l:string = ""
    if !a:report_ignored
      let l:string .= 'SEMVERVE_REPORT_IGNORED=true '
    endif
    let l:string .= 'bundle exec rake semverve:check 2>/dev/null'
    cexpr systemlist(l:string)
    if v:shell_error != 0
      copen
    else
      cclose
      echo 'Semverve checks passed.'
    endif
  finally
    let &errorformat = l:old_efm
  endtry
endfunction
```

You can then call `:SemverveAudit`, which will call `bundle exec rake
semverve:check`, and `:SemverveAudit!` which will call the same command with
`SEMVERVE_REPORT_IGNORED=true`, and populate and open the quickfix list if any
offenses are found.

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
