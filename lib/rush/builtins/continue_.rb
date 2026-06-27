# frozen_string_literal: true

module Rush
  module Builtins
    # `continue [n]` — resume the n-th enclosing loop's next iteration (default 1).
    class Continue < Base
      def call = raise ContinueSignal, level

      private

      def level = operands.first ? operands.first.to_i : 1
    end
  end
end
