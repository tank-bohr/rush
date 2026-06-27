# frozen_string_literal: true

module Rush
  module AST
    # `until cond; do body; done` — runs the body until the condition succeeds.
    class Until < Node
      attr_reader :condition, :body

      def initialize(condition, body)
        super()
        @condition = condition
        @body = body
      end

      def execute(executor) = LoopRunner.new(executor, condition, body, :until).call
    end
  end
end
