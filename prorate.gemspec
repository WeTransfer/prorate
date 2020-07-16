
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'prorate/version'

Gem::Specification.new do |spec|
  spec.name          = "prorate"
  spec.version       = Prorate::VERSION
  spec.authors       = ["Julik Tarkhanov"]
  spec.email         = ["me@julik.nl"]

  spec.summary       = %q{Time-restricted rate limiter using Redis}
  spec.description   = %q{Can be used to implement all kinds of throttles}
  spec.homepage      = "https://github.com/WeTransfer/prorate"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "https://rubygems.org"
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "ks"
  spec.add_dependency "redis", "4.2.1"
  spec.add_development_dependency "connection_pool", "~> 2"
  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency 'wetransfer_style', '0.6.5'
  spec.add_development_dependency 'yard', '~> 0.9'
  spec.add_development_dependency 'pry', '~> 0.12.2'
end
