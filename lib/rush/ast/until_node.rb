# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # `until cond; do body; done` — runs the body until the condition succeeds.
    class Until < Node
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
        LoopRunner.new(executor, condition, body, :until).call
      end
    end
  end
end
