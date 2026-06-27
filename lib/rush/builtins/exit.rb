# frozen_string_literal: true

module Rush
  module Builtins
    # `exit [n]` — unwind to the top level via ExitSignal, carrying the status
    # (the last command's status when no operand is given).
    class Exit < Base
      def call = raise ExitSignal, code

      private

      def code = operands.empty? ? executor.state.last_status.exitstatus : operands.first.to_i
    end
  end
end
