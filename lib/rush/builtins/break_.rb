# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `break [n]` — exit the n-th enclosing loop (default 1); the shared
    # POSIX 2.9.5 semantics live in LoopJump.
    class Break < LoopJump
      extend T::Sig

      private

      sig { returns(T.class_of(LoopControl)) }
      def signal
        BreakSignal
      end
    end
  end
end
