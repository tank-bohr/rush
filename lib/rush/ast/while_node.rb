# frozen_string_literal: true

module Rush
  module AST
    # `while cond; do body; done` — runs the body while the condition succeeds.
    class While < Node
      attr_reader :condition, :body

      def initialize(condition, body)
        super()
        @condition = condition
        @body = body
      end

      def execute(executor) = LoopRunner.new(executor, condition, body, :while).call
    end
  end
end
