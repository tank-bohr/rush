# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = 'rush'
  # Read (not require) the version so the file loads fresh under coverage in specs.
  spec.version = File.read(File.expand_path('lib/rush/version.rb', __dir__))[/VERSION = '([^']+)'/, 1]
  spec.authors = ['tank']
  spec.email = ['tank@bohr.su']

  spec.summary = 'A pure-Ruby POSIX shell (sh) with a Racc-generated parser.'
  spec.description = 'rush implements the POSIX.1-2017 Shell Command Language ' \
                     '(IEEE Std 1003.1 §2) in pure Ruby, verified differentially against dash.'
  spec.homepage = 'https://github.com/tank-bohr/rush'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.4'

  spec.metadata = {
    'rubygems_mfa_required' => 'true',
    'homepage_uri' => spec.homepage,
    'source_code_uri' => spec.homepage
  }

  spec.files = Dir[
    'lib/**/*.rb', 'exe/*', 'grammar/shell.y', 'grammar/shell.y.output',
    'README.md', 'LICENSE'
  ]
  spec.bindir = 'exe'
  spec.executables = ['rush']
  spec.require_paths = ['lib']

  # racc provides BOTH the `racc` compiler (dev/build) and the `racc/parser`
  # runtime that the generated parser requires, so a single dependency covers both.
  spec.add_dependency 'racc', '~> 1.7', '>= 1.7.3'

  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'reek', '~> 6.5'
  spec.add_development_dependency 'rspec', '~> 3.13'
  spec.add_development_dependency 'rubocop', '~> 1.72'
  spec.add_development_dependency 'rubocop-performance', '~> 1.23'
  spec.add_development_dependency 'rubocop-rspec', '~> 3.5'
  spec.add_development_dependency 'simplecov', '~> 0.22'
end
