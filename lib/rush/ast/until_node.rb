# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # `until cond; do body; done` — runs the body until the condition succeeds.
    class Until < ConditionLoop
      extend T::Sig

      private

      sig { returns(Symbol) }
      def kind
        :until
      end
    end
  end
end
