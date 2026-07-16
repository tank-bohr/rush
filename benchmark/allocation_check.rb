# frozen_string_literal: true

require 'json'

module RushBench
  # Compares a current allocation report with the committed baseline and the
  # separately reviewed budgets. The baseline pins what the budgets were
  # reviewed against — context, sampling, workload definitions — while the
  # budgets are the only pass/fail ceilings, so re-recording the baseline can
  # never silently legalize a regression.
  #
  # Unlike the timing check, host/os/cpu are deliberately not compared:
  # allocation counts are a property of the pinned Ruby and the workload, not
  # of the machine, and the gate must hold on CI against a baseline recorded
  # on a developer host.
  class AllocationCheck
    SUPPORTED_SCHEMA = 1
    CONTEXT_KEYS = %w[ruby platform rush_runtime_typechecks sorbet_runtime_default_checked_level_env].freeze
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

      ["unsupported allocation schema: current=#{schemas[0].inspect}, " \
       "baseline=#{schemas[1].inspect}, budgets=#{schemas[2].inspect}"]
    end

    def context_failures
      CONTEXT_KEYS.filter_map do |key|
        "allocation context #{key} differs from the baseline" unless @current.fetch(key) == @baseline.fetch(key)
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

      ['allocation case names differ from the baseline']
    end

    def definition_failures
      common_names.filter_map do |name|
        "#{name}: workload definition differs from the baseline" unless same_definition?(name)
      end
    end

    def budget_coverage_failures
      return [] if budget_map.keys.sort == baseline_cases.keys.sort

      ['allocation budgets do not cover exactly the baseline case set']
    end

    def budget_failures
      common_names.filter_map { |name| budget_failure(name, budget_map[name]) }
    end

    def budget_failure(name, budget)
      observed = current_cases.fetch(name).fetch('median')
      return unless budget && observed > budget

      format('%<name>s: median %<observed>.1f allocated objects exceeds the budget %<budget>d',
             name: name, observed: observed, budget: budget)
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
