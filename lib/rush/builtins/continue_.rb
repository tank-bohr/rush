# frozen_string_literal: true

module Rush
  module Builtins
    # `continue [n]` — resume the n-th enclosing loop's next iteration (default
    # 1). continue is a successful builtin, so it sets $? to 0 before unwinding
    # (POSIX): the next iteration's body and any code after the loop see 0. With
    # no enclosing loop it is a no-op; a level past the actual nesting is clamped.
    class Continue < Base
      def call
        executor.state.last_status = success
        raise ContinueSignal, clamped if executor.state.in_loop?

        success
      end

      private

      def clamped = [level, executor.state.loop_depth].min

      def level = operands.first ? operands.first.to_i : 1
    end
  end
end
