# frozen_string_literal: true

module Rush
  module Builtins
    # Pure evaluator for `test`/`[` expressions. POSIX specifies the result by
    # argument count (XCU `test`), so the arity drives dispatch and the `!`/`( )`
    # groupings recurse into the smaller arities. String and integer primaries
    # live here; file-test primaries (-e, -f, ...) arrive in a later slice. A
    # malformed expression raises TestError, which the builtin maps to exit 2.
    class TestExpr
      SIZES = { 0 => :none?, 1 => :one?, 2 => :two?, 3 => :three?, 4 => :four? }.freeze
      UNARY = { '-n' => :nonempty?, '-z' => :empty? }.freeze
      STRING = { '=' => :==, '!=' => :!= }.freeze
      INTEGER = { '-eq' => :==, '-ne' => :!=, '-gt' => :>, '-ge' => :>=, '-lt' => :<, '-le' => :<= }.freeze

      def initialize(args) = @args = args

      def true? = evaluate(@args)

      private

      def evaluate(args) = send(SIZES.fetch(args.size, :many), args)

      def none?(_args) = false

      def one?(args) = !args.first.empty?

      def two?(args)
        op, val = args
        return !one?([val]) if op == '!'

        unary(op, val)
      end

      def three?(args)
        lhs, op, rhs = args
        return binary(lhs, op, rhs) if binary?(op)
        return !two?([op, rhs]) if lhs == '!'
        return one?([op]) if lhs == '(' && rhs == ')'

        raise TestError, 'syntax error'
      end

      def four?(args)
        return !three?(args.drop(1)) if args.first == '!'
        return two?(args[1..2]) if args.first == '(' && args.last == ')'

        raise TestError, 'syntax error'
      end

      def many(_args) = raise TestError, 'too many arguments'

      def unary(op, val)
        raise TestError, "#{op}: unary operator expected" unless UNARY.key?(op)

        send(UNARY.fetch(op), val)
      end

      def nonempty?(val) = !val.empty?

      def empty?(val) = val.empty?

      def binary?(op) = STRING.key?(op) || INTEGER.key?(op)

      def binary(lhs, op, rhs)
        return lhs.public_send(STRING.fetch(op), rhs) if STRING.key?(op)

        to_int(lhs).public_send(INTEGER.fetch(op), to_int(rhs))
      end

      def to_int(text)
        raise TestError, "#{text}: integer expected" unless text.match?(/\A[+-]?\d+\z/)

        text.to_i
      end
    end
  end
end
