# frozen_string_literal: true

require 'English'

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'dangermattic/gem_version'

Gem::Specification.new do |spec|
  spec.name          = 'danger-dangermattic'
  spec.version       = Dangermattic::VERSION
  spec.author        = 'Automattic'
  spec.email         = 'mobile@automattic.com'
  spec.description   = 'A shared collection of Danger plugins'
  spec.summary       = 'A shared collection of Danger plugins'
  spec.homepage      = 'https://github.com/Automattic/dangermattic'
  spec.license       = 'MPL-2.0'
  spec.files         = `git ls-files`.split($INPUT_RECORD_SEPARATOR)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.required_ruby_version = '~> 3.2'

  spec.add_dependency 'danger', '~> 9.4'
  spec.add_runtime_dependency 'danger-plugin-api', '~> 1.0'

  # Danger plugins
  spec.add_dependency 'danger-junit', '~> 1.0'
  spec.add_dependency 'danger-rubocop', '~> 0.12'
  spec.add_dependency 'danger-swiftlint', '~> 0.35'
  spec.add_dependency 'danger-xcode_summary', '~> 1.0'

  # General ruby development
  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rake', '~> 13.1'

  # Testing support
  spec.add_development_dependency 'rspec', '~> 3.4'

  # Linting code and docs
  spec.add_dependency 'rubocop', '~> 1.60'
  spec.add_development_dependency 'rubocop-rake'
  spec.add_development_dependency 'rubocop-rspec'
  spec.add_development_dependency 'yard'

  # Makes testing easy via `bundle exec guard`
  spec.add_development_dependency 'guard', '~> 2.18'
  spec.add_development_dependency 'guard-rspec', '~> 4.7'

  # This gives you the chance to run a REPL inside your tests
  # via:
  #
  #    require 'pry'
  #    binding.pry
  #
  # This will stop test execution and let you inspect the results
  spec.add_development_dependency 'pry'
end
