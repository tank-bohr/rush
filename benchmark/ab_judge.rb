# frozen_string_literal: true

require_relative 'statistics'

module RushBench
  # Verdict for one workload from paired same-runner cohorts.
  ABVerdict = Data.define(:verdict, :median_delta, :floor)

  # Case-specific, evidence-backed threshold: the noise floor is what this
  # very run measured — the larger side's own cohort spread — bounded below
  # by a minimum absolute delta so microsecond jitter on fast cases cannot
  # flag. A regression needs every paired cohort to agree in sign AND the
  # median paired delta to clear the floor; clearing half the floor is
  # borderline, which earns one extra cohort, not a verdict.
  class ABJudge
    MIN_ABS_MS = 5.0

    def initialize(base_medians, current_medians)
      @base = base_medians
      @current = current_medians
    end

    def verdict
      ABVerdict.new(verdict: decide, median_delta: median_delta, floor: floor)
    end

    private

    def decide
      return :regression if median_delta > floor && deltas.all?(&:positive?)
      return :borderline if median_delta > floor / 2

      :ok
    end

    def deltas
      pairs = @base.zip(@current)
      pairs.map! { |base, current| current - base }
    end

    def median_delta
      RushBench.median(deltas)
    end

    def floor
      [spread(@base), spread(@current), MIN_ABS_MS].max
    end

    def spread(values)
      values.max - values.min
    end
  end
end
