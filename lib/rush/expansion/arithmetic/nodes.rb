# frozen_string_literal: true

module Rush
  module Expansion
    module Arithmetic
      # The arithmetic AST. Each node computes against an Evaluator (`ctx`), which
      # resolves variable names. And/Or and the conditional short-circuit so a
      # branch that is not taken never runs (matching dash, where `0 && 1/0` is 0).
      #
      # Nodes subclass Data.define (rather than carrying methods in its block) so
      # Steep attributes #result to the node, not the enclosing module.

      # A literal integer.
      class Num < Data.define(:value)
        def result(_ctx)
          value
        end
      end

      # A variable reference; resolves its name through the evaluator.
      class Var < Data.define(:name)
        def result(ctx)
          ctx.resolve(name)
        end
      end

      # A unary operation (+ - ! ~) on one operand.
      class Unary < Data.define(:op, :operand)
        def result(ctx)
          Number.unary(op, operand.result(ctx))
        end
      end

      # A binary arithmetic / bitwise / comparison operation on two operands.
      class Binary < Data.define(:op, :left, :right)
        def result(ctx)
          Number.binary(op, left.result(ctx), right.result(ctx))
        end
      end

      # Logical &&: short-circuits, so the right operand runs only when the left is non-zero.
      class And < Data.define(:left, :right)
        def result(ctx)
          left.result(ctx).zero? ? 0 : Number.bool(!right.result(ctx).zero?)
        end
      end

      # Logical ||: short-circuits, so the right operand runs only when the left is zero.
      class Or < Data.define(:left, :right)
        def result(ctx)
          left.result(ctx).zero? ? Number.bool(!right.result(ctx).zero?) : 1
        end
      end

      # The ?: conditional: only the taken branch is evaluated.
      class Cond < Data.define(:test, :truthy, :falsy)
        def result(ctx)
          test.result(ctx).zero? ? falsy.result(ctx) : truthy.result(ctx)
        end
      end

      # The right-hand side is evaluated before the target is read, so a nested
      # assignment in the rhs (e.g. `a += a += 1`) takes effect first.
      class Assign < Data.define(:name, :op, :rhs)
        def result(ctx)
          ctx.assign(name, op, rhs.result(ctx))
        end
      end
    end
  end
end
