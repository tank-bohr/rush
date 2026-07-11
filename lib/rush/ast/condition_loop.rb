# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # Shared shape of the two condition-driven loops: hold the condition and
    # body, delegate to LoopRunner with the subclass's kind — :while runs the
    # body while the condition succeeds, :until until it does.
    class ConditionLoop < Node
      extend T::Sig

      attr_reader :condition, :body

      sig { params(condition: Node, body: Node).void }
      def initialize(condition, body)
        @condition = condition
        @body = body
      end

      sig { params(executor: Executor).returns(Status) }
      def execute(executor)
        LoopRunner.new(executor, condition, body, kind).call
      end

      private

      # The LoopRunner mode this node runs in.
      sig { returns(Symbol) }
      def kind
        raise NotImplementedError
      end
    end
  end
end
