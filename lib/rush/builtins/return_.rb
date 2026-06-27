# frozen_string_literal: true

module Rush
  module Builtins
    # `return [n]` — return from the current function with status n (default: the
    # last command's status).
    class Return < Base
      def call = raise ReturnSignal, code

      private

      def code = operands.first ? operands.first.to_i : executor.state.last_status.exitstatus
    end
  end
end
