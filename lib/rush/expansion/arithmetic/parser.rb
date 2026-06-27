# frozen_string_literal: true

module Rush
  module Expansion
    module Arithmetic
      # A Pratt (precedence-climbing) parser turning the tokens into the AST.
      # Binary precedence is table-driven; the conditional operator (?:) binds
      # loosest and is right-associative. Malformed input or leftover tokens
      # raise a syntax error (matching dash's "expecting primary"/"expecting EOF").
      class Parser
        PRECEDENCE = {
          '||' => 1, '&&' => 2, '|' => 3, '^' => 4, '&' => 5,
          '==' => 6, '!=' => 6, '<' => 7, '<=' => 7, '>' => 7, '>=' => 7,
          '<<' => 8, '>>' => 8, '+' => 9, '-' => 9, '*' => 10, '/' => 10, '%' => 10
        }.freeze
        UNARY = %w[+ - ! ~].freeze

        def initialize(tokens)
          @tokens = tokens
          @pos = 0
        end

        def parse
          node = conditional
          oops unless @pos == @tokens.size
          node
        end

        private

        def conditional
          test = binary(1)
          return test unless accept?('?')

          branch = conditional
          expect(':')
          Cond.new(test, branch, conditional)
        end

        def binary(min)
          left = unary
          left = fold(left) while (power = PRECEDENCE[peek]) && power >= min
          left
        end

        def fold(left)
          op = advance
          combine(op, left, binary(PRECEDENCE[op] + 1))
        end

        def combine(op, left, right)
          return And.new(left, right) if op == '&&'
          return Or.new(left, right) if op == '||'

          Binary.new(op, left, right)
        end

        def unary
          return Unary.new(advance, unary) if UNARY.include?(peek)

          primary
        end

        def primary
          return grouped if accept?('(')

          kind, text = take
          return Num.new(Number.parse(text)) if kind == :num

          kind == :name ? Var.new(text) : oops
        end

        def grouped
          node = conditional
          expect(')')
          node
        end

        def peek = @tokens[@pos]&.last

        def advance = take.last

        def take
          oops if @pos >= @tokens.size
          @tokens[@pos].tap { @pos += 1 }
        end

        def accept?(token)
          return false unless peek == token

          @pos += 1
          true
        end

        def expect(token) = accept?(token) || oops

        def oops = raise(ExpansionError, 'arithmetic: syntax error')
      end
    end
  end
end
