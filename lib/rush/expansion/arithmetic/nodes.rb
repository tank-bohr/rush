# frozen_string_literal: true

module Rush
  module Expansion
    module Arithmetic
      # The arithmetic AST. Each node computes against an Evaluator (`ctx`), which
      # resolves variable names. And/Or and the conditional short-circuit so a
      # branch that is not taken never runs (matching dash, where `0 && 1/0` is 0).
      Num = Data.define(:value) { def result(_ctx) = value }
      # A variable reference; resolves its name through the evaluator.
      Var = Data.define(:name) { def result(ctx) = ctx.resolve(name) }
      # A unary operation (+ - ! ~) on one operand.
      Unary = Data.define(:op, :operand) { def result(ctx) = Number.unary(op, operand.result(ctx)) }
      # A binary arithmetic / bitwise / comparison operation on two operands.
      Binary = Data.define(:op, :left, :right) do
        def result(ctx) = Number.binary(op, left.result(ctx), right.result(ctx))
      end
      # Logical &&: short-circuits, so the right operand runs only when the left is non-zero.
      And = Data.define(:left, :right) do
        def result(ctx) = left.result(ctx).zero? ? 0 : Number.bool(!right.result(ctx).zero?)
      end
      # Logical ||: short-circuits, so the right operand runs only when the left is zero.
      Or = Data.define(:left, :right) do
        def result(ctx) = left.result(ctx).zero? ? Number.bool(!right.result(ctx).zero?) : 1
      end
      # The ?: conditional: only the taken branch is evaluated.
      Cond = Data.define(:test, :truthy, :falsy) do
        def result(ctx) = test.result(ctx).zero? ? falsy.result(ctx) : truthy.result(ctx)
      end
      # The right-hand side is evaluated before the target is read, so a nested
      # assignment in the rhs (e.g. `a += a += 1`) takes effect first.
      Assign = Data.define(:name, :op, :rhs) do
        def result(ctx) = ctx.assign(name, op, rhs.result(ctx))
      end
    end
  end
end
