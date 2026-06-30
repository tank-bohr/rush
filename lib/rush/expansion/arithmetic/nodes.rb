# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    module Arithmetic
      # The arithmetic AST. Each node computes against an Evaluator (`ctx`), which
      # resolves variable names. And/Or and the conditional short-circuit so a
      # branch that is not taken never runs (matching dash, where `0 && 1/0` is 0).
      #
      # Each node is `X = Data.define(...)` with #result added in a reopened class
      # (not the define block): this is the one Data shape BOTH checkers accept —
      # Steep types the reopened methods, while Sorbet rejects `class X <
      # Data.define(...)` ("superclass must be a constant literal"). Style/Documentation
      # documents each on the reopen; reek (which also sees the assignment as a class)
      # exempts them in .reek.yml. See the dual-type-system notes in docs/journal.md.

      Num = Data.define(:value)
      # A literal integer.
      class Num
        extend T::Sig

        sig { params(_ctx: Evaluator).returns(Integer) }
        def result(_ctx)
          value
        end
      end

      Var = Data.define(:name)
      # A variable reference; resolves its name through the evaluator.
      class Var
        extend T::Sig

        sig { params(ctx: Evaluator).returns(Integer) }
        def result(ctx)
          ctx.resolve(name)
        end
      end

      Unary = Data.define(:op, :operand)
      # A unary operation (+ - ! ~) on one operand.
      class Unary
        extend T::Sig

        sig { params(ctx: Evaluator).returns(Integer) }
        def result(ctx)
          Number.unary(op, operand.result(ctx))
        end
      end

      Binary = Data.define(:op, :left, :right)
      # A binary arithmetic / bitwise / comparison operation on two operands.
      class Binary
        extend T::Sig

        sig { params(ctx: Evaluator).returns(Integer) }
        def result(ctx)
          Number.binary(op, left.result(ctx), right.result(ctx))
        end
      end

      And = Data.define(:left, :right)
      # Logical &&: short-circuits, so the right operand runs only when the left is non-zero.
      class And
        extend T::Sig

        sig { params(ctx: Evaluator).returns(Integer) }
        def result(ctx)
          left.result(ctx).zero? ? 0 : Number.bool(!right.result(ctx).zero?)
        end
      end

      Or = Data.define(:left, :right)
      # Logical ||: short-circuits, so the right operand runs only when the left is zero.
      class Or
        extend T::Sig

        sig { params(ctx: Evaluator).returns(Integer) }
        def result(ctx)
          left.result(ctx).zero? ? Number.bool(!right.result(ctx).zero?) : 1
        end
      end

      Cond = Data.define(:test, :truthy, :falsy)
      # The ?: conditional: only the taken branch is evaluated.
      class Cond
        extend T::Sig

        sig { params(ctx: Evaluator).returns(Integer) }
        def result(ctx)
          test.result(ctx).zero? ? falsy.result(ctx) : truthy.result(ctx)
        end
      end

      Assign = Data.define(:name, :op, :rhs)
      # The right-hand side is evaluated before the target is read, so a nested
      # assignment in the rhs (e.g. `a += a += 1`) takes effect first.
      class Assign
        extend T::Sig

        sig { params(ctx: Evaluator).returns(Integer) }
        def result(ctx)
          ctx.assign(name, op, rhs.result(ctx))
        end
      end
    end
  end
end
