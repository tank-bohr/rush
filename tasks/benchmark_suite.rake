# frozen_string_literal: true

BENCHMARK_BASELINE = 'benchmark/baseline.json'
BENCHMARK_RUNNER = [Gem.ruby, 'benchmark/run.rb'].freeze

# A transitive development gem installs an unrelated top-level benchmark task.
Rake::Task['benchmark'].clear if Rake::Task.task_defined?('benchmark')

desc 'Run the opt-in startup, loop, and expansion performance suite'
task benchmark: :compile do
  sh(*BENCHMARK_RUNNER)
end

namespace :benchmark do
  desc 'Compare benchmark medians with the committed baseline (default tolerance 1.5x)'
  task check: :compile do
    sh(*BENCHMARK_RUNNER, '--check', BENCHMARK_BASELINE)
  end

  desc 'Record benchmark medians and environment metadata as the new baseline'
  task record: :compile do
    sh(*BENCHMARK_RUNNER, '--json', BENCHMARK_BASELINE)
  end
end
