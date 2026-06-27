# frozen_string_literal: true

module Rush
  # Runs a while/until loop, catching break/continue at the loop boundary (see
  # LoopControlHandling). The loop's status is the last body status (0 if the
  # body never runs).
  class LoopRunner
    include LoopControlHandling

    def initialize(executor, condition, body, sense)
      @executor = executor
      @condition = condition
      @body = body
      @sense = sense
    end

    def call
      status = Status.success
      status = iterate while proceed?
      status
    rescue BreakSignal => e
      unwind(e)
    end

    private

    def proceed?
      met = @executor.tested { @executor.run(@condition) }.success?
      @sense == :while ? met : !met
    end

    def iterate
      @executor.run(@body)
    rescue ContinueSignal => e
      unwind(e)
    end
  end
end
