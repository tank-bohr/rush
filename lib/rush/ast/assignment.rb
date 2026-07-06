# typed: true
# frozen_string_literal: true

module Rush
  module AST
    # `name=value` — value is an unexpanded Word (it receives tilde and the
    # step-1 expansions, but no field splitting or pathname expansion).
    Assignment = Data.define(:name, :value)

    # Behaviour for the Data-defined assignment payload.
    class Assignment
      extend T::Sig

      sig { returns(Integer) }
      def source_line
        value.source_line
      end
    end
  end
end
