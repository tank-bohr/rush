# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `export name[=value] ...` — mark each name for inclusion in the environment
    # of subsequently executed commands, assigning the value first when one is
    # given. (The `-p` listing form arrives with the variable-printing slice.)
    class Export < Base
      extend T::Sig

      sig { returns(T.untyped) }
      def call
        operands.each { |operand| declare(operand) }
        success
      end

      private

      sig { params(operand: T.untyped).returns(T.untyped) }
      def declare(operand)
        executor.state.variables.export_operand(operand)
      end
    end
  end
end
