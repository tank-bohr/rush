# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # Shared engine of `break` and `continue` (POSIX 2.9.5). Both are successful
    # builtins, so they set $? to 0 before unwinding: the status is seen after
    # the loop, and by the next iteration's body. With no enclosing loop the
    # builtin is a no-op; a level past the actual nesting is clamped, so
    # `break 5` in two loops exits both. The level (>= 1) is validated even
    # with no loop, so `break abc` still aborts. Subclasses name the signal
    # that carries the level up to the enclosing loop runner.
    class LoopJump < Base
      extend T::Sig

      sig { returns(Status) }
      def call
        level = validated
        executor.state.record_status(success)
        raise signal, clamped(level) if executor.state.loops.any?

        success
      end

      private

      # The LoopControl subclass this builtin unwinds with.
      sig { returns(T.class_of(LoopControl)) }
      def signal
        raise NotImplementedError
      end

      sig { returns(Integer) }
      def validated
        first = operands.first
        first ? numeric_operand(first, min: 1) : 1
      end

      sig { params(level: Integer).returns(Integer) }
      def clamped(level)
        [level, executor.state.loops.depth].min
      end
    end
  end
end
