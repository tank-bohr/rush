# frozen_string_literal: true

module Rush
  module Builtins
    # `shift [n]` — discard the first n positional parameters (default 1) and
    # renumber the rest. When n exceeds the parameter count nothing changes and
    # the status is non-zero; rush does not abort as a special builtin would.
    class Shift < Base
      def call
        return report if count > state.positional.size

        state.positional = state.positional.drop(count)
        success
      end

      private

      def state = executor.state

      def count = operands.first&.to_i || 1

      def report
        stderr.puts("rush: shift: can't shift that many")
        failure
      end
    end
  end
end
