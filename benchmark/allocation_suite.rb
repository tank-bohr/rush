# frozen_string_literal: true

require_relative 'cases'
require_relative 'suite'

module RushBench
  # Sampling policy for the in-process allocation counter.
  AllocationSampling = Data.define(:samples, :warmups)

  # Counts objects allocated by the canonical interpreter workloads. Runs
  # in-process (the injected runner drives Rush::CLI inside this Ruby) so the
  # GC.stat delta attributes to interpretation alone — no subprocess or
  # VM-boot noise — which is what makes the counts deterministic enough to
  # ratchet where wall-clock timings are not.
  class AllocationSuite
    CASE_NAMES = %w[parse_heavy dispatch_heavy while_arithmetic expansion_heavy].freeze

    def self.canonical_cases
      CASES.select { |entry| CASE_NAMES.include?(entry.name) }
    end

    def initialize(runner:, sampling:, cases: AllocationSuite.canonical_cases)
      @runner = runner
      @sampling = sampling
      @cases = cases
    end

    def run
      @cases.to_h { |benchmark_case| [benchmark_case, counts(benchmark_case)] }
    end

    private

    def counts(benchmark_case)
      @sampling.warmups.times { execute(benchmark_case) }
      Array.new(@sampling.samples) { sample(benchmark_case) }
    end

    def sample(benchmark_case)
      GC.start
      before = GC.stat(:total_allocated_objects)
      execute(benchmark_case)
      GC.stat(:total_allocated_objects) - before
    end

    def execute(benchmark_case)
      status = @runner.call(benchmark_case.source)
      return if status.zero?

      raise ExecutionError, "allocation workload #{benchmark_case.name} failed with status #{status}"
    end
  end
end
