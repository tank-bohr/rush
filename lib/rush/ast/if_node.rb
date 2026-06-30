# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # `if cond; then body; [elif/else ...] fi`. Runs the condition list; on
    # success runs the consequent, otherwise the alternative (an else List, a
    # nested If for elif, or nil). With no matching branch the status is 0.
    class If < Node
      extend T::Sig

      attr_reader :condition, :consequent, :alternative

      sig { params(condition: Node, consequent: Node, alternative: T.nilable(Node)).void }
      def initialize(condition, consequent, alternative)
        super()
        @condition = condition
        @consequent = consequent
        @alternative = alternative
      end

      sig { params(executor: Executor).returns(Status) }
      def execute(executor)
        return executor.run(consequent) if executor.succeeds?(condition)

        alternative ? executor.run(alternative) : Status.success
      end
    end
  end
end
