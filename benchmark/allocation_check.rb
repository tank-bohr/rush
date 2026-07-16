# frozen_string_literal: true

require_relative 'baseline_check'

module RushBench
  # The allocation ratchet: medians of in-process object counts against the
  # reviewed per-workload ceilings (see BaselineCheck for the frame).
  #
  # Unlike the timing check, host/os/cpu are deliberately not compared:
  # allocation counts are a property of the pinned Ruby and the workload, not
  # of the machine, and the gate must hold on CI against a baseline recorded
  # on a developer host.
  class AllocationCheck < BaselineCheck
    CONTEXT_KEYS = %w[ruby platform rush_runtime_typechecks sorbet_runtime_default_checked_level_env].freeze

    private

    def label
      'allocation'
    end

    def context_keys
      CONTEXT_KEYS
    end

    def observed(case_hash)
      case_hash.fetch('median')
    end

    def budget_failure_message(name, observed, budget)
      format('%<name>s: median %<observed>.1f allocated objects exceeds the budget %<budget>d',
             name: name, observed: observed, budget: budget)
    end
  end
end
