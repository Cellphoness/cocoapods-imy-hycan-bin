require_relative 'lib/cocoapods/imy/hycan/bin/version'

Gem::Specification.new do |spec|
  spec.name          = "cocoapods-imy-hycan-bin"
  spec.version       = Cocoapods::Imy::Hycan::Bin::VERSION
  spec.authors       = ["fengjx"]
  spec.email         = ["1026366384@qq.com"]

  spec.summary       = "copy of cocoapods-imy--bin"
  spec.description   = "cocoapods-imy-bin copy source and prmotion for hycan"
  spec.homepage      = "https://github.com/Cellphoness/cocoapods-imy-hycan-bin"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "https://rubygems.org"
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/Cellphoness/cocoapods-imy-hycan-bin.git"
  # spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir["lib/**/*.rb","spec/**/*.rb","lib/**/*.plist"] + %w{README.md LICENSE.txt }
  # spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency 'parallel'
  spec.add_dependency 'cocoapods'
  spec.add_dependency "cocoapods-generate",'~>2.0.1'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake'
end
