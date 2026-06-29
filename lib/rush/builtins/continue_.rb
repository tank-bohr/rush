# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `continue [n]` — resume the n-th enclosing loop's next iteration (default
    # 1). continue is a successful builtin, so it sets $? to 0 before unwinding
    # (POSIX): the next iteration's body and any code after the loop see 0. With
    # no enclosing loop it is a no-op; a level past the actual nesting is clamped.
    # The level (>= 1) is validated even with no loop, so `continue abc` aborts.
    class Continue < Base
      def call
        level = validated
        executor.state.record_status(success)
        raise ContinueSignal, clamped(level) if executor.state.loops.any?

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
