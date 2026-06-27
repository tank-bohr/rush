# frozen_string_literal: true

module Rush
  module Builtins
    # `break [n]` — exit the n-th enclosing loop (default 1). break is a
    # successful builtin, so it sets $? to 0 before unwinding (POSIX): the status
    # is seen after the loop, and after a `continue` in the next iteration's body.
    class Break < Base
      def call
        executor.state.last_status = success
        raise BreakSignal, level
      end

      private

      def level = operands.first ? operands.first.to_i : 1
    end
  end
end
