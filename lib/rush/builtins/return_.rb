# frozen_string_literal: true

module Rush
  module Builtins
    # `return [n]` — return from the current function with status n (default: the
    # last command's status). A non-numeric n is a special-builtin error.
    class Return < Base
      def call = raise ReturnSignal, code

      private

      def code = operands.first ? numeric_operand(operands.first) : executor.state.last_status.exitstatus
    end
  end
end
