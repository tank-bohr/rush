# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # The impure inputs to one test/[ evaluation: the filesystem port plus the
    # resolver that projects shell-level fd bindings onto unary operands.
    class TestContext
      extend T::Sig

      sig { params(files: SystemCalls, fd_operand: FdOperand).void }
      def initialize(files, fd_operand)
        @files = files
        @fd_operand = fd_operand
      end

      sig { params(operator: String, operand: String).returns(T::Boolean) }
      def unary(operator, operand)
        resolved = @fd_operand.resolve(operator, operand)
        TestOperators.unary(operator).call(@files, resolved)
      end
    end
  end
end
