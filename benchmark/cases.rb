# frozen_string_literal: true

require 'rbconfig'

# Stable workloads and subprocess commands for rush's opt-in performance suite.
module RushBench
  ROOT = File.expand_path('..', __dir__)
  Case = Data.define(:name, :description, :iterations, :source)
  Target = Data.define(:name, :command, :environment)

  CASES = [
    Case.new(name: 'startup', description: 'parse and execute a no-op', iterations: 1, source: ':'),
    Case.new(
      name: 'while_arithmetic', description: '10,000 while/test/arithmetic increments', iterations: 10_000,
      source: 'i=0; while [ "$i" -lt 10000 ]; do i=$((i + 1)); done; test "$i" -eq 10000'
    ),
    Case.new(
      name: 'expansion_heavy', description: '2,000 command-free parameter expansion rounds', iterations: 2_000,
      source: <<~SH
        i=0
        value=alpha/beta/gamma.txt
        while [ "$i" -lt 2000 ]; do
          head=${value%%/*}; tail=${value##*/}; stem=${tail%.*}
          joined=${head}_${stem}_${i:-0}; i=$((i + 1))
        done
        test "$joined" = alpha_gamma_1999
      SH
    )
  ].freeze

  module_function

  def targets
    [Target.new(name: 'rush', command: rush_command, environment: bare_environment),
     Target.new(name: 'dash', command: [ENV.fetch('DASH', '/usr/bin/dash'), '-c'], environment: {})]
  end

  def rush_command
    load_flags = runtime_load_paths.flat_map { |path| ['-I', path] }
    [RbConfig.ruby, *load_flags, "-I#{File.join(ROOT, 'lib')}", File.join(ROOT, 'exe/rush'), '-c']
  end

  def runtime_load_paths
    %w[sorbet-runtime racc reline fiddle].flat_map do |name|
      Gem::Specification.find_by_name(name).full_require_paths
    end
  end

  def bare_environment
    { 'RUBYOPT' => nil, 'RUBYLIB' => nil, 'BUNDLE_GEMFILE' => nil, 'BUNDLE_BIN_PATH' => nil }
  end
end
