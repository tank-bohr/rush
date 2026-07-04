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

      sig { returns(Status) }
      def call
        return not_in_function unless state.variables.in_function?

        operands.each { |operand| declare(operand) }
        success
      end

      private

      sig { returns(ShellState) }
      def state
        executor.state
      end

      sig { params(operand: String).void }
      def declare(operand)
        state.variables.declare_local_operand(operand)
      end

      sig { returns(Status) }
      def not_in_function
        stderr.puts('rush: local: not in a function')
        failure(2)
      end
    end
  end
end
