# frozen_string_literal: true

module Rush
  module Builtins
    # `break [n]` — exit the n-th enclosing loop (default 1).
    class Break < Base
      def call = raise BreakSignal, level

      private

      def level = operands.first ? operands.first.to_i : 1
    end
  end
end
