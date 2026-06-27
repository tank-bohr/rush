# frozen_string_literal: true

module Rush
  module AST
    # `pipeline && pipeline` / `pipeline || pipeline`, left-associative. Runs the
    # left side, then the right side only when the operator's short-circuit allows.
    class AndOr < Node
      attr_reader :left, :op, :right

      def initialize(left, op, right)
        super()
        @left = left
        @op = op
        @right = right
      end

      # The left side is non-final, so it runs in a tested context (errexit
      # suppressed); only the final command's status reaches the errexit check.
      def execute(executor)
        status = executor.tested { executor.run(left) }
        run_right?(status) ? executor.run(right) : status
      end

      private

      def run_right?(status) = op == :and ? status.success? : !status.success?
    end
  end
end
