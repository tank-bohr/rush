# frozen_string_literal: true

require 'json'

module RushBench
  # Shared frame for the benchmark ratchets: a current report is compared
  # against the committed baseline (context, sampling, and workload identity
  # must match) and against a separately reviewed budgets file, which holds
  # the only pass/fail ceilings — so re-recording a baseline can never
  # silently legalize a regression. Subclasses supply the label, the compared
  # context keys, the observed metric, and the breach message.
  class BaselineCheck
    SUPPORTED_SCHEMA = 1
    DEFINITION_KEYS = %w[description iterations source_sha256].freeze

    def self.load(path)
      JSON.parse(File.read(path))
    end

    def initialize(current, baseline, budgets)
      @current = current
      @baseline = baseline
      @budgets = budgets
    end

    def failures
      schema_failures + context_failures + sampling_failures + case_set_failures +
        definition_failures + budget_coverage_failures + budget_failures
    end

    private

    def schema_failures
      schemas = [@current.fetch('schema'), @baseline.fetch('schema'), @budgets.fetch('schema')]
      return [] if schemas.all?(SUPPORTED_SCHEMA)

      ["unsupported #{label} schema: current=#{schemas[0].inspect}, " \
       "baseline=#{schemas[1].inspect}, budgets=#{schemas[2].inspect}"]
    end

    def context_failures
      context_keys.filter_map do |key|
        "#{label} context #{key} differs from the baseline" unless @current.fetch(key) == @baseline.fetch(key)
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

      ["#{label} case names differ from the baseline"]
    end

    def definition_failures
      common_names.filter_map do |name|
        "#{name}: workload definition differs from the baseline" unless same_definition?(name)
      end
    end

    def budget_coverage_failures
      return [] if budget_map.keys.sort == baseline_cases.keys.sort

      ["#{label} budgets do not cover exactly the baseline case set"]
    end

    def budget_failures
      common_names.filter_map { |name| budget_failure(name, budget_map[name]) }
    end

    def budget_failure(name, budget)
      observed = observed(current_cases.fetch(name))
      return unless budget && observed > budget

      budget_failure_message(name, observed, budget)
    end

    def same_definition?(name)
      DEFINITION_KEYS.all? { |key| current_cases.fetch(name).fetch(key) == baseline_cases.fetch(name).fetch(key) }
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

    def budget_map
      @budgets.fetch('budgets')
    end
  end
end
