# Upgrading Semverve

## Version 0.4.0

This release changes Semverve's version-check API so Rails and other app
frameworks can be supported without pretending every project is a gem package.

### Breaking changes

- `:metadata` was removed from `config.version_checks`.
- `semverve:check:metadata` and `semverve:fix:metadata` were removed.
- Use `:package_metadata`, `semverve:check:package_metadata`, and
  `semverve:fix:package_metadata` for gemspec and `Gemfile.lock` checks.
- Rails defaults no longer include package metadata checks.
- Rails apps no longer infer a package name from `config/version.rb`.

### Rails apps

Use the Rails adapter:

```ruby
Semverve.configure do |config|
  config.adapter = :rails
end
```

`config.preset = :rails` still works for compatibility, but `config.adapter` is
the preferred API.

Rails defaults now use:

```ruby
[:doc_references, :code_references, :rails_config_metadata]
```

Rails config metadata is optional. If Semverve finds safe literals like these,
it checks and can fix them:

```ruby
config.x.version = "1.2.3"
Rails.application.config.x.version = "1.2.3"
```

Dynamic assignments are treated as self-managed:

```ruby
config.x.version = Storefront::VERSION
```

Rails engines or apps that publish gems can opt back into package metadata:

```ruby
Semverve.configure do |config|
  config.adapter = :rails
  config.gem_name = "my_engine"
  config.version_checks = [:doc_references, :code_references, :rails_config_metadata, :package_metadata]
end
```

### Sinatra apps

Sinatra apps can opt into app-style defaults:

```ruby
Semverve.configure do |config|
  config.adapter = :sinatra
end
```

The Sinatra adapter uses `config/version.rb`, `:simple` format, and default
checks of `[:doc_references, :code_references]`.

### Extension API

Framework integration now goes through `Semverve::Adapters`, and version-check
integration goes through `Semverve::VersionChecks`. Checks should return
`Semverve::Finding` objects from `findings` and `Semverve::FixResult` from
`fix`.
