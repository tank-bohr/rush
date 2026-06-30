# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    module Arithmetic
      # A Pratt (precedence-climbing) parser turning the tokens into the AST.
      # Binary precedence is table-driven; the conditional operator (?:) binds
      # loosest and is right-associative. Malformed input or leftover tokens
      # raise a syntax error (matching dash's "expecting primary"/"expecting EOF").
      class Parser
        extend T::Sig

        PRECEDENCE = {
          '||' => 1, '&&' => 2, '|' => 3, '^' => 4, '&' => 5,
          '==' => 6, '!=' => 6, '<' => 7, '<=' => 7, '>' => 7, '>=' => 7,
          '<<' => 8, '>>' => 8, '+' => 9, '-' => 9, '*' => 10, '/' => 10, '%' => 10
        }.freeze
        UNARY = %w[+ - ! ~].freeze
        ASSIGN = ['=', '+=', '-=', '*=', '/=', '%=', '<<=', '>>=', '&=', '^=', '|='].freeze

        sig { params(tokens: T::Array[[Symbol, String]]).void }
        def initialize(tokens)
          @tokens = tokens
          @pos = 0
        end

        sig { returns(T.any(Num, Var, Unary, Binary, And, Or, Cond, Assign)) }
        def parse
          node = assignment
          oops unless @pos == @tokens.size
          node
        end

        private

        # Assignment binds loosest and is right-associative; its target must be a
        # bare name (an lvalue), so e.g. `5 = 3` is a syntax error.
        sig { returns(T.any(Num, Var, Unary, Binary, And, Or, Cond, Assign)) }
        def assignment
          left = conditional
          return left unless ASSIGN.include?(peek)

          oops unless left.is_a?(Var)
          Assign.new(left.name, advance, assignment)
        end

        sig { returns(T.any(Num, Var, Unary, Binary, And, Or, Cond, Assign)) }
        def conditional
          test = binary(1)
          return test unless accept?('?')

          branch = assignment
          expect(':')
          Cond.new(test, branch, conditional)
        end

        sig { params(min: Integer).returns(T.any(Num, Var, Unary, Binary, And, Or, Cond, Assign)) }
        def binary(min)
          left = unary
          left = fold(left) while (tok = peek) && (power = PRECEDENCE[tok]) && power >= min
          left
        end

        sig do
          params(left: T.any(Num, Var, Unary, Binary, And, Or, Cond, Assign))
            .returns(T.any(Num, Var, Unary, Binary, And, Or, Cond, Assign))
        end
        def fold(left)
          op = advance
          combine(op, left, binary(PRECEDENCE.fetch(op) + 1))
        end

        sig do
          params(op: String,
                 left: T.any(Num, Var, Unary, Binary, And, Or, Cond, Assign),
                 right: T.any(Num, Var, Unary, Binary, And, Or, Cond, Assign))
            .returns(T.any(Num, Var, Unary, Binary, And, Or, Cond, Assign))
        end
        def combine(op, left, right)
          return And.new(left, right) if op == '&&'
          return Or.new(left, right) if op == '||'

          Binary.new(op, left, right)
        end

        sig { returns(T.any(Num, Var, Unary, Binary, And, Or, Cond, Assign)) }
        def unary
          # `find` (not `include?`) hands back the matching UNARY element, so under
          # Steep — where UNARY is Array[unary_op] — `op` carries the literal
          # operator type into Unary.new instead of a bare scanned String. This is
          # the narrowing point that makes the RBS literal union reachable; Sorbet,
          # with no string-literal types, still sees String. See docs/journal.md.
          token = peek
          op = UNARY.find { |candidate| candidate == token }
          return primary unless op

          advance
          Unary.new(op, unary)
        end

        sig { returns(T.any(Num, Var, Unary, Binary, And, Or, Cond, Assign)) }
        def primary
          return grouped if accept?('(')

          kind, text = take
          return Num.new(Number.parse(text)) if kind == :num

          kind == :name ? Var.new(text) : oops
        end

        sig { returns(T.any(Num, Var, Unary, Binary, And, Or, Cond, Assign)) }
        def grouped
          node = assignment
          expect(')')
          node
        end

        sig { returns(T.nilable(String)) }
        def peek
          @tokens[@pos]&.last
        end

        sig { returns(String) }
        def advance
          take.last
        end

        sig { returns([Symbol, String]) }
        def take
          oops if @pos >= @tokens.size
          @tokens.fetch(@pos).tap { @pos += 1 }
        end

        sig { params(token: String).returns(T::Boolean) }
        def accept?(token)
          return false unless peek == token

          @pos += 1
          true
        end

        sig { params(token: String).void }
        def expect(token)
          accept?(token) || oops
        end

        sig { returns(T.noreturn) }
        def oops
          raise(ExpansionError, 'arithmetic: syntax error')
        end
      end
    end
  end
end
