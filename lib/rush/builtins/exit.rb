# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `exit [n]` — unwind to the top level via ExitSignal, carrying the status n
    # (the executor's exiting status when no operand is given: the last command's
    # status normally, or the shell's terminating status inside the EXIT trap).
    # A non-numeric n is a special-builtin error.
    class Exit < Base
      extend T::Sig

      sig { returns(T.untyped) }
      def call
        raise ExitSignal, code
      end

      private

      sig { returns(T.untyped) }
      def code
        operands.empty? ? executor.trap_runner.exiting_status : numeric_operand(T.must(operands.first))
      end
    end
  end
end
