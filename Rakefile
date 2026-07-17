# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'json'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'
require_relative 'tasks/sorbet_coverage'

load 'tasks/compile.rake'
load 'tasks/docker.rake'
load 'tasks/complexity.rake'
load 'tasks/benchmark_suite.rake'

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

# Generated parser must exist before linting or testing.
task spec: :compile
task rubocop: :compile

desc 'Code-smell gate (reek; config + rationale in .reek.yml)'
task :reek do
  # Production code only (lib + exe); reek runs as a forward-looking ratchet.
  sh 'reek lib exe'
end

desc 'Type-check gate (Steep over RBS sigs in sig/; config + rollout in Steepfile)'
task :steep do
  # RBS/Steep is one of two independent type checkers (see docs/journal.md).
  sh 'steep check'
end

SORBET_COVERAGE_BASELINE = 'sorbet/coverage_baseline.json'
SORBET_COVERAGE_BUDGETS = 'sorbet/coverage_budgets.json'
SORBET_BINARY = File.join(Gem::Specification.find_by_name('sorbet-static').full_gem_path, 'libexec', 'sorbet')

desc 'Type-check plus typed-send ratchet (Sorbet; independent of Steep)'
task :sorbet do
  # The raw binary reads only sorbet/config, avoiding unrelated gem RBIs that
  # the srb wrapper discovers. One pass supplies both errors and ratchet data.
  SorbetCoverage.check!(binary: SORBET_BINARY,
                        baseline_path: SORBET_COVERAGE_BASELINE,
                        budgets_path: SORBET_COVERAGE_BUDGETS)
end

namespace :sorbet do
  namespace :coverage do
    desc 'Record Sorbet version, exact input scope, and observations (never changes budgets)'
    task record: :compile do
      SorbetCoverage.record!(binary: SORBET_BINARY, baseline_path: SORBET_COVERAGE_BASELINE)
    end
  end
end

# Mutant exits non-zero when any mutation survives. The threshold gate therefore
# evaluates Mutant's JSON result instead of treating that non-zero status as an
# automatic failure.
module MutantRake
  module_function

  def latest_result(previous)
    candidates = Dir['.mutant/results/*.json'] - previous
    (candidates.empty? ? Dir['.mutant/results/*.json'] : candidates).max_by { |path| File.mtime(path) }
  end

  def counts(path)
    JSON.parse(File.read(path)).fetch('subject_results').each_with_object(Hash.new(0)) do |subject, totals|
      count_subject(subject, totals)
    end
  end

  def count_subject(subject, totals)
    subject.fetch('coverage_results').each { |result| count_criteria(result.fetch('criteria_result'), totals) }
  end

  def count_criteria(criteria, totals)
    totals[:total] += 1
    totals[category(criteria)] += 1
  end

  def category(criteria)
    return :timeout if criteria.fetch('timeout')

    criteria.fetch('test_result') ? :killed : :alive
  end

  def score(counts)
    return 100.0 if counts[:total].zero?

    ((counts[:killed] + counts[:timeout]) * 100.0) / counts[:total]
  end

  def score_line(score, threshold, result)
    format('Mutant score: %<score>.2f%% (threshold %<threshold>.2f%%) from %<result>s',
           score: score, threshold: threshold, result: result)
  end

  def summary(counts)
    format('Mutants: %<total>d, killed: %<killed>d, timeouts: %<timeout>d, alive: %<alive>d', counts)
  end

  def failure(score, threshold)
    format('Mutant score %<score>.2f%% is below %<threshold>.2f%%', score: score, threshold: threshold)
  end
end

# Ratchet floor at the measured baseline: the 2026-07-16 burn-down (slices
# 18x-19c: ~645 mutants killed via targeted unit vectors, five justified
# fiddle-lifecycle ignores, and one dead-return refactor) measured 96.08%
# (38643 mutants, 1516 alive) — the floor sits one notch under, ~31 mutants
# of slack. Raise further as alive mutants burn down (rush-tqq tracks the
# ratchet); never lower it to admit new survivors.
MUTANT_DEFAULT_THRESHOLD = 96.0
MUTANT_DEFAULT_SUBJECT = 'Rush*'

namespace :mutant do
  desc 'Mutation threshold gate (on-demand). Optional: rake mutant:check[Rush*,95.0]'
  task :check, %i[subject threshold] => :compile do |_task, args|
    previous = Dir['.mutant/results/*.json']
    subject = args[:subject] || ENV.fetch('MUTANT_SUBJECT', MUTANT_DEFAULT_SUBJECT)
    threshold = Float(args[:threshold] || ENV.fetch('MUTANT_THRESHOLD', MUTANT_DEFAULT_THRESHOLD.to_s))

    system('mutant', 'run', subject)
    result = MutantRake.latest_result(previous) || abort('mutant:check could not find a Mutant JSON result')
    counts = MutantRake.counts(result)
    score = MutantRake.score(counts)

    puts MutantRake.score_line(score, threshold, result)
    puts MutantRake.summary(counts)
    abort MutantRake.failure(score, threshold) if score < threshold
  end
end

desc 'Mutation-test run (Mutant; on-demand, not part of default). Optional: rake mutant[Rush::Status]'
task :mutant, [:subject] => :compile do |_task, args|
  command = %w[mutant run]
  subject = args[:subject] || ENV.fetch('MUTANT_SUBJECT', nil)

  command << subject if subject && !subject.empty?

  sh(*command)
end

load 'tasks/quality.rake'
