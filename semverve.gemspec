require_relative "lib/semverve/version"

Gem::Specification.new do |spec|
  spec.name = "semverve"
  spec.version = Semverve::VERSION
  spec.authors = ["Evan Gray"]
  spec.email = "evanthegrayt@vivaldi.net"
  spec.license = "MIT"

  spec.summary = %(Rake tasks for managing Ruby gem version files)
  spec.description = %(Semverve adds Rake tasks that read, generate, and increment Ruby gem version files.)
  spec.homepage = "https://github.com/evanthegrayt/semverve"
  spec.required_ruby_version = ">= 3.2"

  unless spec.respond_to?(:metadata)
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/evanthegrayt/semverve"
  spec.metadata["documentation_uri"] = "https://evanthegrayt.github.io/semverve/"

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir = "bin"
  spec.executables = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.add_development_dependency "rake", "~> 13.0", ">= 13.0.1"
  spec.add_development_dependency "rdoc"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "standard", "~> 1.54.0"
  spec.add_development_dependency "test-unit", "~> 3.3", ">= 3.3.5"
end
