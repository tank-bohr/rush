# frozen_string_literal: true

module Rush
  module Builtins
    # `continue [n]` — resume the n-th enclosing loop's next iteration (default
    # 1). continue is a successful builtin, so it sets $? to 0 before unwinding
    # (POSIX): the next iteration's body and any code after the loop see 0.
    class Continue < Base
      def call
        executor.state.last_status = success
        raise ContinueSignal, level
      end

      private

      def level = operands.first ? operands.first.to_i : 1
    end
  end
end
