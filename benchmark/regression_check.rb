# frozen_string_literal: true

require 'json'

module RushBench
  # Compares rush medians with an explicitly requested recorded baseline. Dash
  # stays report-only: it is useful context, not a stable timing denominator.
  class RegressionCheck
    SUPPORTED_SCHEMA = 1
    CONTEXT_KEYS = %w[ruby platform host os cpu sorbet_runtime_default_checked_level].freeze
    DEFINITION_KEYS = %w[description iterations source_sha256].freeze

    def initialize(current, baseline, tolerance: 1.5)
      @current = current
      @baseline = baseline
      @tolerance = tolerance
    end

    def failures
      schema_failures + context_failures + sampling_failures + case_set_failures +
        definition_failures + timing_failures
    end

    def self.load(path)
      JSON.parse(File.read(path))
    end

    private

    def schema_failures
      schemas = [@current.fetch('schema'), @baseline.fetch('schema')]
      return [] if schemas.all?(SUPPORTED_SCHEMA)

      ["unsupported benchmark schema: current=#{schemas.first.inspect}, baseline=#{schemas.last.inspect}"]
    end

    def context_failures
      CONTEXT_KEYS.filter_map do |key|
        "benchmark context #{key} differs from the baseline" unless @current.fetch(key) == @baseline.fetch(key)
      end
    end

    def sampling_failures
      failures = []
      failures << 'sample count is lower than the baseline' if @current.fetch('samples') < @baseline.fetch('samples')
      failures << 'warmup count is lower than the baseline' if @current.fetch('warmups') < @baseline.fetch('warmups')
      failures
    end

    def case_set_failures
      return [] if current_cases.keys.sort == baseline_cases.keys.sort

      ['benchmark case names differ from the baseline']
    end

    def definition_failures
      common_names.filter_map do |name|
        "#{name}: workload definition differs from the baseline" unless same_definition?(name)
      end
    end

    def timing_failures
      common_names.filter_map { |name| timing_failure(name, baseline_cases.fetch(name)) }
    end

    def same_definition?(name)
      current = current_cases.fetch(name)
      baseline = baseline_cases.fetch(name)
      DEFINITION_KEYS.all? { |key| current.fetch(key) == baseline.fetch(key) }
    end

    def timing_failure(name, expected)
      observed = rush_median(current_cases.fetch(name))
      limit = rush_median(expected) * @tolerance
      return if observed <= limit

      format('%<name>s: %<observed>.3fms exceeds %<limit>.3fms', name: name, observed: observed, limit: limit)
    end

    def common_names
      current_cases.keys & baseline_cases.keys
    end

    def current_cases
      @current.fetch('cases')
    end

    def baseline_cases
      @baseline.fetch('cases')
    end

    def rush_median(benchmark_case)
      benchmark_case.fetch('targets').fetch('rush').fetch('median_ms')
    end
  end
end
