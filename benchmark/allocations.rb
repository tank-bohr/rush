#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'cases'
require_relative '../lib/rush/runtime_type_checks'

Rush::RuntimeTypeChecks.configure
require_relative '../lib/rush'

samples = Integer(ENV.fetch('RUSH_BENCH_SAMPLES', '5'), 10)
warmups = Integer(ENV.fetch('RUSH_BENCH_WARMUPS', '1'), 10)
abort 'RUSH_BENCH_SAMPLES must be positive' unless samples.positive?
abort 'RUSH_BENCH_WARMUPS must be non-negative' if warmups.negative?

cases = RushBench::CASES.select { |entry| %w[while_arithmetic expansion_heavy].include?(entry.name) }
run = lambda do |entry|
  status = Rush::CLI.run(['-c', entry.source])
  abort "allocation workload #{entry.name} failed with status #{status}" if status.nonzero?
end

puts "Ruby #{RUBY_VERSION}; #{samples} allocation samples after #{warmups} warmup(s)"
cases.each do |entry|
  warmups.times { run.call(entry) }
  counts = Array.new(samples) do
    GC.start
    before = GC.stat(:total_allocated_objects)
    run.call(entry)
    GC.stat(:total_allocated_objects) - before
  end
  sorted = counts.sort
  median = (sorted[(counts.length - 1) / 2] + sorted[counts.length / 2]) / 2.0
  values = { name: entry.name, median: median, samples: counts.join(', ') }
  puts format('%<name>-20s %<median>12.1f  [%<samples>s]', values)
end
