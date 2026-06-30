# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `shift [n]` — discard the first n positional parameters (default 1) and
    # renumber the rest. As a special builtin, two errors abort a non-interactive
    # shell with status 2 (BuiltinError, firing the EXIT trap), matching dash: a
    # non-numeric / negative operand ("Illegal number"), and asking to shift more
    # than $# ("can't shift that many"). Extra operands past the first are ignored.
    class Shift < Base
      extend T::Sig

      sig { returns(T.untyped) }
      def call
        raise BuiltinError, "shift: can't shift that many" if count > state.positional.size

        state.positional.shift(count)
        success
      end

      private

      sig { returns(T.untyped) }
      def state
        executor.state
      end

      sig { returns(T.untyped) }
      def count
        operands.empty? ? 1 : numeric_operand(T.must(operands.first))
      end
    end
  end
end
