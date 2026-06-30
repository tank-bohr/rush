# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # `while cond; do body; done` — runs the body while the condition succeeds.
    class While < Node
      extend T::Sig

      attr_reader :condition, :body

      sig { params(condition: Node, body: Node).void }
      def initialize(condition, body)
        super()
        @condition = condition
        @body = body
      end

      sig { params(executor: Executor).returns(Status) }
      def execute(executor)
        LoopRunner.new(executor, condition, body, :while).call
      end
    end
  end
end
