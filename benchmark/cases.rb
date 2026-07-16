# frozen_string_literal: true

require 'rbconfig'

# Stable workloads and subprocess commands for rush's opt-in performance suite.
module RushBench
  ROOT = File.expand_path('..', __dir__)
  Case = Data.define(:name, :description, :iterations, :source)
  Target = Data.define(:name, :command, :environment)

  # A grammar-dense function body multiplied into a large source: the
  # functions are defined but never called, so the workload is parse/lex
  # dominated while remaining a valid POSIX program for both shells. IDX
  # keeps each copy textually distinct so no caching layer can collapse them.
  PARSE_CHUNK = <<~'SH'
    fIDX() {
      case "$1" in
        a | b*) x="${1:-default}" && y=$((IDX + 1)) ;;
        *) for v in one "two three" 'four'; do x="$v$x${y:-}"; done ;;
      esac
      while [ "${#x}" -gt 99 ]; do x=${x%?}; done
      printf '%s\n' "$x" > /dev/null 2>&1
    }
  SH

  def self.parse_heavy_source
    "#{(1..220).map { |index| PARSE_CHUNK.gsub('IDX', index.to_s) }.join}:"
  end

  CASES = [
    Case.new(name: 'startup', description: 'parse and execute a no-op', iterations: 1, source: ':'),
    Case.new(
      name: 'parse_heavy', description: '220 grammar-dense function definitions, parsed but never called',
      iterations: 220, source: parse_heavy_source
    ),
    Case.new(
      name: 'dispatch_heavy', description: '2,500 rounds of nested function and builtin dispatch',
      iterations: 2_500,
      source: <<~SH
        f() { :; }
        g() { f; }
        i=0
        while [ "$i" -lt 2500 ]; do g; f; :; true; i=$((i + 1)); done
        test "$i" -eq 2500
      SH
    ),
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
