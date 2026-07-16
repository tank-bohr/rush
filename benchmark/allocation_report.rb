# frozen_string_literal: true

require 'digest'
require 'json'

require_relative 'context'
require_relative 'statistics'

module RushBench
  # Converts AllocationSuite counts into the versioned, machine-readable
  # schema the allocation ratchet compares, and a compact table for humans.
  # Raw counts stay in the JSON so later analysis is not constrained to
  # today's summary statistics.
  class AllocationReport
    SCHEMA = 1

    def initialize(results, samples:, warmups:)
      @results = results
      @samples = samples
      @warmups = warmups
    end

    def to_h
      Context.snapshot.merge(
        'schema' => SCHEMA, 'samples' => @samples, 'warmups' => @warmups, 'cases' => cases_hash
      )
    end

    def to_json(*)
      JSON.pretty_generate(to_h)
    end

    def print_table(io = $stdout)
      io.puts "Ruby #{RUBY_VERSION}; #{@samples} allocation samples after #{@warmups} warmup(s); " \
              "runtime checks=#{Context.runtime_typechecks}"
      @results.each { |benchmark_case, counts| io.puts row(benchmark_case, counts) }
    end

    private

    def cases_hash
      @results.to_h { |benchmark_case, counts| [benchmark_case.name, case_hash(benchmark_case, counts)] }
    end

    def case_hash(benchmark_case, counts)
      { 'description' => benchmark_case.description, 'iterations' => benchmark_case.iterations,
        'source_sha256' => Digest::SHA256.hexdigest(benchmark_case.source),
        'counts' => counts, 'median' => RushBench.median(counts) }
    end

    def row(benchmark_case, counts)
      format('%<name>-20s %<median>14.1f  [%<counts>s]',
             name: benchmark_case.name, median: RushBench.median(counts), counts: counts.join(', '))
    end
  end
end
