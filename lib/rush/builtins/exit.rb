# frozen_string_literal: true

module Rush
  module Builtins
    # `exit [n]` — unwind to the top level via ExitSignal, carrying the status n
    # (the executor's exiting status when no operand is given: the last command's
    # status normally, or the shell's terminating status inside the EXIT trap).
    # A non-numeric n is a special-builtin error.
    class Exit < Base
      def call
        raise ExitSignal, code
      end

      private

      def code
        operands.empty? ? executor.trap_runner.exiting_status : numeric_operand(operands.first)
      end
    end
  end
end
