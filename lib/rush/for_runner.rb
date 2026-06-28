# frozen_string_literal: true

module Rush
  # Runs a for loop: assign the variable to each value in turn and run the body,
  # catching break/continue at the loop boundary (see LoopControlHandling). The
  # loop's status is the last body status (0 if the value list is empty).
  class ForRunner
    include LoopControlHandling

    def initialize(executor, name, values, body)
      @executor = executor
      @name = name
      @values = values
      @body = body
    end

    # Bracket the loop so break/continue see the right nesting depth (see
    # LoopNesting#enter via state.loops); leave runs even when break unwinds.
    def call
      @executor.state.loops.enter
      run_loop
    ensure
      @executor.state.loops.leave
    end

    private

    def run_loop
      status = Status.success
      @values.each { |value| status = iterate(value) }
      status
    rescue BreakSignal => e
      unwind(e)
    end

    def iterate(value)
      @executor.state.environment.assign(@name, value)
      @executor.run(@body)
    rescue ContinueSignal => e
      unwind(e)
    end
  end
end
