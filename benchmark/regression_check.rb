# frozen_string_literal: true

require_relative 'baseline_check'

module RushBench
  # The timing alarm: rush medians against reviewed per-workload millisecond
  # ceilings (see BaselineCheck for the frame). Wall-clock is not
  # deterministic, so this stays a host-local catastrophic alarm — the full
  # context including host/os/cpu must match the committed baseline, and dash
  # remains report-only context, never a timing denominator.
  class RegressionCheck < BaselineCheck
    CONTEXT_KEYS = %w[
      ruby platform host os cpu rush_runtime_typechecks sorbet_runtime_default_checked_level_env
    ].freeze

    private

    def label
      'benchmark'
    end

    def context_keys
      CONTEXT_KEYS
    end

    def observed(case_hash)
      case_hash.fetch('targets').fetch('rush').fetch('median_ms')
    end

    def budget_failure_message(name, observed, budget)
      format('%<name>s: %<observed>.3fms exceeds the budget %<budget>.3fms',
             name: name, observed: observed, budget: budget)
    end
  end
end
