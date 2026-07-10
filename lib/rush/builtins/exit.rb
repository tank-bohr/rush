# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `exit [n]` — unwind to the top level via ExitSignal, carrying the status n
    # (the executor's exiting status when no operand is given: the last command's
    # status normally, or the shell's terminating status inside the EXIT trap).
    # A non-numeric n is a special-builtin error. With a stopped job in the
    # table the first exit is refused — "You have stopped jobs.", status 0 —
    # and an immediately repeated exit goes through (dash's stoppedjobs
    # guard, probed batch and interactive alike; only the interactive prompt
    # loop re-arms the warning).
    class Exit < Base
      extend T::Sig

      sig { returns(Status) }
      def call
        return refuse_stopped if executor.jobs.refuse_exit?

        raise ExitSignal, code
      end

      private

      sig { returns(Status) }
      def refuse_stopped
        stderr.puts('You have stopped jobs.')
        success
      end

      sig { returns(Integer) }
      def code
        operands.empty? ? executor.trap_runner.exiting_status : numeric_operand(operands.fetch(0))
      end
    end
  end
end
