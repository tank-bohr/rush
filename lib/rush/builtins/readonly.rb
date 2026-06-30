# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `readonly name[=value] ...` — assign the value (when given) and mark each
    # name read only, so a later assignment or unset aborts (see ReadonlyError).
    # (The `-p` listing form arrives with the variable-printing slice.)
    class Readonly < Base
      extend T::Sig

      sig { returns(T.untyped) }
      def call
        operands.each { |operand| declare(operand) }
        success
      end

      private

      sig { params(operand: T.untyped).returns(T.untyped) }
      def declare(operand)
        name, value = operand.split('=', 2)
        environment.assign(name, value) if value
        environment.readonly(name)
      end

      sig { returns(T.untyped) }
      def environment
        executor.state.environment
      end
    end
  end
end
