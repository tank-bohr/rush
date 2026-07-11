# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # `while cond; do body; done` — runs the body while the condition succeeds.
    class While < ConditionLoop
      extend T::Sig

      private

      sig { returns(Symbol) }
      def kind
        :while
      end
    end
  end
end
