# typed: true
# frozen_string_literal: true

module Rush
  # Runs a while/until loop, catching break/continue at the loop boundary (see
  # LoopControlHandling). The loop's status is the last body status (0 if the
  # body never runs).
  class LoopRunner
    extend T::Sig

    include LoopControlHandling

    sig { params(executor: Executor, condition: AST::Node, body: AST::Node, sense: Symbol).void }
    def initialize(executor, condition, body, sense)
      @executor = executor
      @condition = condition
      @body = body
      @sense = sense
    end

    # Bracket the loop so break/continue see the right nesting depth; leave runs
    # even when break unwinds.
    sig { returns(Status) }
    def call
      @executor.state.with_loop { run_loop }
    end

    private

    sig { returns(Status) }
    def run_loop
      # T.let pins the loop variable's type: Status.success is now sig'd (Status),
      # but #iterate is unsig'd (untyped), and Sorbet forbids a variable changing
      # type across a loop (srb.help/7001). Steep ignores T.let (see sorbet_dsl.rbs).
      status = T.let(Status.success, Status)
      status = iterate while proceed?
      status
    rescue BreakSignal => e
      unwind(e)
    end

    sig { returns(T::Boolean) }
    def proceed?
      met = @executor.succeeds?(@condition)
      @sense == :while ? met : !met
    end

    sig { returns(Status) }
    def iterate
      @executor.run(@body)
    rescue ContinueSignal => e
      unwind(e)
    end
  end
end
