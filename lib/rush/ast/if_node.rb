# frozen_string_literal: true

module Rush
  module AST
    # `if cond; then body; [elif/else ...] fi`. Runs the condition list; on
    # success runs the consequent, otherwise the alternative (an else List, a
    # nested If for elif, or nil). With no matching branch the status is 0.
    class If < Node
      attr_reader :condition, :consequent, :alternative

      def initialize(condition, consequent, alternative)
        super()
        @condition = condition
        @consequent = consequent
        @alternative = alternative
      end

      def execute(executor)
        return executor.run(consequent) if condition_met?(executor)

        alternative ? executor.run(alternative) : Status.success
      end

      private

      # The condition runs in a tested context so a failing test never trips errexit.
      def condition_met?(executor) = executor.tested { executor.run(condition) }.success?
    end
  end
end
