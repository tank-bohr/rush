# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `test EXPR` / `[ EXPR ]` — evaluate a conditional expression, returning
    # success (0) when true and failure (1) when false. A malformed expression
    # is reported on stderr with exit status 2. Invoked as `[`, the expression
    # must be terminated by a closing `]`.
    class Test < Base
      extend T::Sig

      sig { returns(T.untyped) }
      def call
        evaluate(bracketed? ? without_close(operands) : operands)
      rescue TestError => e
        report(e.message)
      end

      private

      sig { returns(T.untyped) }
      def bracketed?
        argv.first == '['
      end

      sig { params(ops: T.untyped).returns(T.untyped) }
      def without_close(ops)
        *body, close = ops
        raise TestError, "missing `]'" unless close == ']'

        body
      end

      sig { params(ops: T.untyped).returns(T.untyped) }
      def evaluate(ops)
        TestExpr.new(ops, executor.system).true? ? success : failure
      end

      sig { params(message: T.untyped).returns(T.untyped) }
      def report(message)
        stderr.puts("rush: #{argv.first}: #{message}")
        failure(2)
      end
    end
  end
end
