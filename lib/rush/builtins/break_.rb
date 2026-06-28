# frozen_string_literal: true

module Rush
  module Builtins
    # `break [n]` — exit the n-th enclosing loop (default 1). break is a
    # successful builtin, so it sets $? to 0 before unwinding (POSIX): the status
    # is seen after the loop, and after a `continue` in the next iteration's body.
    # With no enclosing loop it is a no-op; a level past the actual nesting is
    # clamped, so `break 5` in two loops exits both (POSIX 2.9.5 "break"). The
    # level (>= 1) is validated even with no loop, so `break abc` still aborts.
    class Break < Base
      def call
        level = validated
        executor.state.record_status(success)
        raise BreakSignal, clamped(level) if executor.state.loops.any?

        success
      end

      private

      def validated
        operands.first ? numeric_operand(operands.first, min: 1) : 1
      end

      def clamped(level)
        [level, executor.state.loops.depth].min
      end
    end
  end
end
