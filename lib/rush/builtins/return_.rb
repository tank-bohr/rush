# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `return [n]` — return from the current function with status n (default: the
    # last command's status). A non-numeric n is a special-builtin error.
    class Return < Base
      def call
        raise ReturnSignal, code
      end

      private

      def code
        operands.first ? numeric_operand(T.must(operands.first)) : executor.state.last_status.exitstatus
      end
    end
  end
end
