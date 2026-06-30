# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `local name[=value] ...` — inside a function, mark each name as local so its
    # prior value is restored when the function returns. A bare name keeps its
    # current value (dash semantics); name=value also assigns. Used outside a
    # function it is an error with status 2.
    class Local < Base
      extend T::Sig

      sig { returns(T.untyped) }
      def call
        return not_in_function unless state.scope.in_function?

        operands.each { |operand| declare(operand) }
        success
      end

      private

      sig { returns(T.untyped) }
      def state
        executor.state
      end

      sig { params(operand: T.untyped).returns(T.untyped) }
      def declare(operand)
        name, value = operand.split('=', 2)
        state.scope.declare_local(name)
        state.environment.assign(name, value) if value
      end

      sig { returns(T.untyped) }
      def not_in_function
        stderr.puts('rush: local: not in a function')
        failure(2)
      end
    end
  end
end
