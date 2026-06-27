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

      def execute(executor)
        status = executor.run(left)
        run_right?(status) ? executor.run(right) : status
      end

      private

      def run_right?(status) = op == :and ? status.success? : !status.success?
    end
  end
end
