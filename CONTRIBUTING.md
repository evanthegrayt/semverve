# Contributing
Thanks for helping improve Semverve. This project is small on purpose, so the
best contributions tend to keep behavior explicit, tests close to the feature,
and release automation boring.

## Ruby and Dependencies
Use the Ruby version declared in `.ruby-version` for local development. The
gemspec declares the supported Ruby floor, while `.ruby-version` records the
maintainer's preferred local runtime.

Install dependencies with:

```sh
bundle install
```

The project has no runtime dependencies outside Ruby, Rake, RubyGems, and
Bundler. Development dependencies are listed in `semverve.gemspec`.

## Test Suite
Run the full default check with:

```sh
bundle exec rake
```

The default task runs:

```sh
bundle exec rake test
bundle exec rake semverve:check
```

Tests live under `test/semverve` and use `test-unit`. The suite exercises the
Rake tasks through temporary project directories so changes are tested the way a
real gem or Rails app would use them. `test/test_helper.rb` also enables
SimpleCov, so test runs print line coverage.

Prefer adding focused tests near the behavior you change:

- format parsing and replacement behavior belongs in format tests
- Rake task behavior belongs in task tests
- version value-object behavior belongs in semantic version tests
- release metadata expectations belong in version or task tests

## Style
Semverve uses Standard Ruby. Check style with:

```sh
bundle exec rake standard
```

You can ask Standard to fix safe offenses with:

```sh
bundle exec rake standard:fix
```

Keep comments useful but sparse. Public constants, classes, modules, attributes,
and methods should have RDoc comments; internal code should usually be clear
from naming and tests.

## Documentation
Build the API documentation with:

```sh
bundle exec rake rerdoc
```

Check documentation coverage with:

```sh
bundle exec rake rdoc:coverage
```

RDoc uses `README.md` as the main page and documents files under `lib/**/*.rb`.
Generated documentation is written to `docs/`, which is ignored on development
branches. The generated site is maintained on the `gh-pages` branch for GitHub
Pages.

Publish generated docs with:

```sh
bundle exec rake docs:publish
```

That task runs `rerdoc`, opens `gh-pages` in a temporary Git worktree, copies
the generated `docs/` output there, commits changed docs, pushes to
`origin/gh-pages`, and removes the temporary worktree. To preview whether
publishing would change the docs branch without committing or pushing, run:

```sh
bundle exec rake docs:publish:dry_run
```

Keep public RDoc comments current as code changes so `bundle exec rake
rdoc:coverage` stays clean and the published API docs remain useful.

When changing behavior, update the README at the same time. The README is the
primary user guide, so examples should match real task names, configuration
names, defaults, and output.

## Rake Task Interface Design
Semverve should feel natural from a shell while staying Rake-native. Prefer
Rake task arguments for direct task inputs:

```sh
bundle exec rake 'semverve:set[x.y.z]'
bundle exec rake 'semverve:generate[simple,force]'
```

For tasks with more than one optional value, prefer meaning-bearing tokens over
strict positional placeholders. For example, `semverve:generate` treats semantic
versions as the generated version, `module` or `simple` as the format, and
`force` as the overwrite mode. That keeps invocations like
`rake 'semverve:generate[simple]'` and `rake 'semverve:generate[force]'`
readable without requiring awkward empty slots.

Use Rake task arguments for one-off exact inputs, such as
`rake 'semverve:check[1.2.3]'` when a user wants to scan only for a specific
version.

Reserve environment variables for cross-cutting runtime toggles that compose
across related tasks, such as `SEMVERVE_REPORT_IGNORED=true rake
semverve:check`. Avoid generic environment variables like `VERSION`, `FORMAT`,
or `FORCE`; they can collide with a user's shell, CI, or parent build process.

## Versioning and Release Checks
Semverve uses Semverve to maintain itself, which doubles as useful
smoke-testing. The project Rakefile requires `lib/semverve/task` and installs
`Semverve::Task` with this project-specific configuration:

```ruby
Semverve::Task.new do |t|
  t.bundle_lock = true
  t.version_code_reference_files.append("lib/**/*.rb", "semverve.gemspec", "Rakefile")
end
```

That means the local `semverve:*` tasks are the same tasks the gem provides to
users. The current version is stored in `lib/semverve/version.rb`, the gemspec
uses `Semverve::VERSION`, and `Gemfile.lock` is checked for drift.

Useful commands:

```sh
bundle exec rake semverve:current
bundle exec rake semverve:increment:patch
bundle exec rake semverve:increment:minor
bundle exec rake semverve:increment:major
bundle exec rake 'semverve:set[x.y.z]'
bundle exec rake semverve:check
bundle exec rake semverve:fix
```

Because `bundle_lock` is enabled for this repository, successful version updates
also run `bundle lock`. The self-check scans README version references,
configured code literals, the gemspec version, and the lockfile entry.

## Release Sanity Checks
Before release, run:

```sh
bundle exec rake
bundle exec rake standard
bundle exec rake rdoc:coverage
bundle exec rake rerdoc
bundle exec rake build
bundle exec rake docs:publish:dry_run
```

The build task writes the packaged gem under `pkg/`. Inspect the package if you
changed metadata or file lists:

```sh
gem specification pkg/semverve-*.gem
```

For a public release, also confirm that the GitHub repository is public, the
gemspec metadata URLs resolve, and RubyGems credentials are configured locally.
