# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `export name[=value] ...` — mark each name for inclusion in the environment
    # of subsequently executed commands; see Declare for the shared engine.
    # (The `-p` listing form arrives with the variable-printing slice.)
    class Export < Declare
      extend T::Sig

      private

      sig { params(operand: String).void }
      def declare(operand)
        executor.state.variables.export_operand(operand)
      end
    end
  end
end
