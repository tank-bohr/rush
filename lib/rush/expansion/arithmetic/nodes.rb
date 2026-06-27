# frozen_string_literal: true

module Rush
  module Expansion
    module Arithmetic
      # The arithmetic AST. Each node computes against an Evaluator (`ctx`), which
      # resolves variable names. And/Or and the conditional short-circuit so a
      # branch that is not taken never runs (matching dash, where `0 && 1/0` is 0).
      Num = Data.define(:value) { def result(_ctx) = value }
      Var = Data.define(:name) { def result(ctx) = ctx.resolve(name) }
      Unary = Data.define(:op, :operand) { def result(ctx) = Number.unary(op, operand.result(ctx)) }
      Binary = Data.define(:op, :left, :right) do
        def result(ctx) = Number.binary(op, left.result(ctx), right.result(ctx))
      end
      And = Data.define(:left, :right) do
        def result(ctx) = left.result(ctx).zero? ? 0 : Number.bool(!right.result(ctx).zero?)
      end
      Or = Data.define(:left, :right) do
        def result(ctx) = left.result(ctx).zero? ? Number.bool(!right.result(ctx).zero?) : 1
      end
      Cond = Data.define(:test, :truthy, :falsy) do
        def result(ctx) = test.result(ctx).zero? ? falsy.result(ctx) : truthy.result(ctx)
      end
    end
  end
end
