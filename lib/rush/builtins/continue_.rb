# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `continue [n]` — resume the n-th enclosing loop's next iteration
    # (default 1); the shared POSIX 2.9.5 semantics live in LoopJump.
    class Continue < LoopJump
      extend T::Sig

      private

      sig { returns(T.class_of(LoopControl)) }
      def signal
        ContinueSignal
      end
    end
  end
end
