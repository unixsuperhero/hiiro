require_relative "lib/hiiro/version"

Gem::Specification.new do |spec|
  spec.name          = "hiiro"
  spec.version       = Hiiro::VERSION
  spec.authors       = ["Joshua Toyota"]
  spec.email         = ["jearsh+rubygems@gmail.com"]

  spec.summary       = "A lightweight CLI framework for Ruby"
  spec.description   = "Build multi-command CLI tools with subcommand dispatch, abbreviation matching, and a plugin system. Similar to git or docker command structure."
  spec.homepage      = "https://github.com/unixsuperhero/hiiro"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[test/ spec/ features/ .git .github .circleci appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "pry", "~> 0.14"
  spec.add_dependency "front_matter_parser"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
