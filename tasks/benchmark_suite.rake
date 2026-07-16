# frozen_string_literal: true

BENCHMARK_BASELINE = 'benchmark/baseline.json'
BENCHMARK_BUDGETS = 'benchmark/timing_budgets.json'
BENCHMARK_RUNNER = [Gem.ruby, 'benchmark/run.rb'].freeze
ALLOCATION_RUNNER = [Gem.ruby, 'benchmark/allocations.rb'].freeze
ALLOCATION_BASELINE = 'benchmark/allocation_baseline.json'
ALLOCATION_BUDGETS = 'benchmark/allocation_budgets.json'

# A transitive development gem installs an unrelated top-level benchmark task.
Rake::Task['benchmark'].clear if Rake::Task.task_defined?('benchmark')

desc 'Run the opt-in startup, loop, and expansion performance suite'
task benchmark: :compile do
  sh(*BENCHMARK_RUNNER)
end

namespace :benchmark do
  desc 'Check timing medians against the recorded baseline and the reviewed budgets (host-local alarm)'
  task check: :compile do
    sh(*BENCHMARK_RUNNER, '--check', BENCHMARK_BASELINE, '--budgets', BENCHMARK_BUDGETS)
  end

  desc 'Record benchmark medians and environment metadata as the new baseline'
  task record: :compile do
    sh(*BENCHMARK_RUNNER, '--json', BENCHMARK_BASELINE)
  end

  desc 'Count allocations for the canonical interpreter workloads (three samples by default)'
  task allocations: :compile do
    sh(*ALLOCATION_RUNNER)
  end

  namespace :allocations do
    desc 'Record allocation counts and context as the committed baseline (never touches budgets)'
    task record: :compile do
      sh(*ALLOCATION_RUNNER, '--json', ALLOCATION_BASELINE)
    end

    desc 'Check allocation medians against the recorded baseline and the reviewed budgets'
    task check: :compile do
      sh(*ALLOCATION_RUNNER, '--check', ALLOCATION_BASELINE, '--budgets', ALLOCATION_BUDGETS)
    end
  end

  desc 'Profile both interpreter workloads in StackProf CPU, wall, and object modes'
  task profile: :compile do
    policy = ENV['RUSH_RUNTIME_TYPECHECKS'] == '1' ? 'checked' : 'unchecked'
    %w[while_arithmetic expansion_heavy].product(%w[cpu wall object]).each do |case_name, mode|
      dump = "tmp/stackprof-#{case_name}-#{mode}-#{policy}.dump"
      sh Gem.ruby, 'benchmark/profile.rb', case_name, mode, dump
      sh Gem.ruby, Gem.bin_path('stackprof', 'stackprof'), dump, '--text', '--limit', '20'
    end
  end
end
