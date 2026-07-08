# Changelog

## Version 0.4.1
- Removed the documentation publisher from the release workflow.

## Version 0.4.0
- Made Rails a first-class adapter with app-oriented defaults.
- Added a Sinatra adapter for app-style version files.
- Replaced the old `:metadata` check with `:package_metadata` for gemspec and
  `Gemfile.lock` checks.
- Stopped inferring package names for Rails and Sinatra apps.
- Moved framework integration through `Semverve::Adapters` and version-check
  integration through `Semverve::VersionChecks`.
