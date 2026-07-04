# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    module Arithmetic
      # The arithmetic AST. Each node computes against an Evaluator (`ctx`), which
      # resolves variable names. And/Or and the conditional short-circuit so a
      # branch that is not taken never runs (matching dash, where `0 && 1/0` is 0).
      #
      # The node payloads are ordinary typed Ruby state rather than generated
      # reader methods: both Steep (via RBS) and Sorbet (via inline sigs) can see
      # the operator/name/child invariants carried through parser and evaluator.
      Node = T.type_alias { T.any(Num, Var, Unary, Binary, And, Or, Cond, Assign) }

      # A literal integer.
      class Num
        extend T::Sig

        sig { returns(Integer) }
        attr_reader :value

        sig { params(value: Integer).void }
        def initialize(value)
          @value = value
        end

        sig { params(_ctx: Evaluator).returns(Integer) }
        def result(_ctx)
          value
        end
      end

      # A variable reference; resolves its name through the evaluator.
      class Var
        extend T::Sig

        sig { returns(String) }
        attr_reader :name

        sig { params(name: String).void }
        def initialize(name)
          @name = name
        end

        sig { params(ctx: Evaluator).returns(Integer) }
        def result(ctx)
          ctx.resolve(name)
        end
      end

      # A unary operation (+ - ! ~) on one operand.
      class Unary
        extend T::Sig

        sig { returns(String) }
        attr_reader :op

        sig { returns(Node) }
        attr_reader :operand

        sig { params(op: String, operand: Node).void }
        def initialize(op, operand)
          @op = op
          @operand = operand
        end

        sig { params(ctx: Evaluator).returns(Integer) }
        def result(ctx)
          Number.unary(op, operand.result(ctx))
        end
      end

      # A binary arithmetic / bitwise / comparison operation on two operands.
      class Binary
        extend T::Sig

        sig { returns(String) }
        attr_reader :op

        sig { returns(Node) }
        attr_reader :left, :right

        sig { params(op: String, left: Node, right: Node).void }
        def initialize(op, left, right)
          @op = op
          @left = left
          @right = right
        end

        sig { params(ctx: Evaluator).returns(Integer) }
        def result(ctx)
          Number.binary(op, left.result(ctx), right.result(ctx))
        end
      end

      # Logical &&: short-circuits, so the right operand runs only when the left is non-zero.
      class And
        extend T::Sig

        sig { returns(Node) }
        attr_reader :left, :right

        sig { params(left: Node, right: Node).void }
        def initialize(left, right)
          @left = left
          @right = right
        end

        sig { params(ctx: Evaluator).returns(Integer) }
        def result(ctx)
          left.result(ctx).zero? ? 0 : Number.bool(!right.result(ctx).zero?)
        end
      end

      # Logical ||: short-circuits, so the right operand runs only when the left is zero.
      class Or
        extend T::Sig

        sig { returns(Node) }
        attr_reader :left, :right

        sig { params(left: Node, right: Node).void }
        def initialize(left, right)
          @left = left
          @right = right
        end

        sig { params(ctx: Evaluator).returns(Integer) }
        def result(ctx)
          left.result(ctx).zero? ? Number.bool(!right.result(ctx).zero?) : 1
        end
      end

      # The ?: conditional: only the taken branch is evaluated.
      class Cond
        extend T::Sig

        sig { returns(Node) }
        attr_reader :test, :truthy, :falsy

        sig { params(test: Node, truthy: Node, falsy: Node).void }
        def initialize(test, truthy, falsy)
          @test = test
          @truthy = truthy
          @falsy = falsy
        end

        sig { params(ctx: Evaluator).returns(Integer) }
        def result(ctx)
          test.result(ctx).zero? ? falsy.result(ctx) : truthy.result(ctx)
        end
      end

      # The right-hand side is evaluated before the target is read, so a nested
      # assignment in the rhs (e.g. `a += a += 1`) takes effect first.
      class Assign
        extend T::Sig

        sig { returns(String) }
        attr_reader :name, :op

        sig { returns(Node) }
        attr_reader :rhs

        sig { params(name: String, op: String, rhs: Node).void }
        def initialize(name, op, rhs)
          @name = name
          @op = op
          @rhs = rhs
        end

        sig { params(ctx: Evaluator).returns(Integer) }
        def result(ctx)
          ctx.assign(name, op, rhs.result(ctx))
        end
      end
    end
  end
end
