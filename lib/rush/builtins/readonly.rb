# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `readonly name[=value] ...` — mark each name read only, so a later
    # assignment or unset aborts (ReadonlyError); see Declare for the shared
    # engine. (The `-p` listing form arrives with the variable-printing slice.)
    class Readonly < Declare
      extend T::Sig

      private

      sig { params(operand: String).void }
      def declare(operand)
        executor.state.variables.readonly_operand(operand)
      end
    end
  end
end
