# frozen_string_literal: true

module Rush
  # Runs a while/until loop, catching break/continue control signals at the loop
  # boundary. A multi-level signal (count > 1) is re-raised with one fewer level
  # so the next enclosing loop handles it. The loop's status is the last body
  # status (or 0 if the body never runs).
  class LoopRunner
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
      met = @executor.run(@condition).success?
      @sense == :while ? met : !met
    end

    def iterate
      @executor.run(@body)
    rescue ContinueSignal => e
      unwind(e)
    end

    def unwind(signal)
      relayed = relay(signal)
      raise relayed if relayed

      @executor.state.last_status
    end

    def relay(signal)
      signal.class.new(signal.count - 1) if signal.count > 1
    end
  end
end
