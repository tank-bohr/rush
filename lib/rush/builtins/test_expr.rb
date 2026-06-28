# frozen_string_literal: true

module Rush
  module Builtins
    # Pure evaluator for `test`/`[` expressions. POSIX specifies the result by
    # argument count (XCU `test`), so #evaluate peels the structural layers —
    # a leading `!` negates the rest, a `( … )` wrapper drops to its contents —
    # recursing until what is left is a primary it dispatches by arity (0 → false,
    # 1 → non-empty, 2 → unary like -n/-f, 3 → binary like = / -eq). The one
    # exception POSIX bakes in: at three arguments a binary primary outranks the
    # `!`/`( )` reading, so it is tried first. String and integer primaries live
    # here; file-test primaries arrive via @files. A malformed expression raises
    # TestError, which the builtin maps to exit 2.
    class TestExpr
      PRIMARY = { 0 => :none?, 1 => :nonempty?, 2 => :unary }.freeze
      STRING_UNARY = { '-n' => :nonempty?, '-z' => :empty? }.freeze
      FILE_UNARY = { '-e' => :exist?, '-f' => :file?, '-d' => :directory?, '-r' => :readable?,
                     '-w' => :writable?, '-x' => :executable?, '-s' => :file_nonempty?,
                     '-h' => :symlink?, '-L' => :symlink? }.freeze
      STRING = { '=' => :==, '!=' => :!= }.freeze
      INTEGER = { '-eq' => :==, '-ne' => :!=, '-gt' => :>, '-ge' => :>=, '-lt' => :<, '-le' => :<= }.freeze

      def initialize(args, files)
        @args = args
        @files = files
      end

      def true? = evaluate(@args)

      private

      def evaluate(args)
        raise TestError, 'too many arguments' if args.size > 4
        return binary(*args) if args.size == 3 && binary?(args[1])
        return !evaluate(args[1..]) if args.first == '!'
        return evaluate(args[1...-1]) if wrapped?(args)

        primary(args)
      end

      def wrapped?(args) = args.size >= 3 && args.first == '(' && args.last == ')'

      def primary(args) = send(PRIMARY.fetch(args.size, :bad), *args)

      def none? = false

      def bad(*) = raise(TestError, 'syntax error')

      def unary(op, val)
        return send(STRING_UNARY.fetch(op), val) if STRING_UNARY.key?(op)
        return @files.public_send(FILE_UNARY.fetch(op), val) if FILE_UNARY.key?(op)

        raise TestError, "#{op}: unary operator expected"
      end

      def nonempty?(val) = !val.empty?

      def empty?(val) = val.empty?

      def binary?(op) = STRING.key?(op) || INTEGER.key?(op)

      def binary(lhs, op, rhs)
        return lhs.public_send(STRING.fetch(op), rhs) if STRING.key?(op)

        to_int(lhs).public_send(INTEGER.fetch(op), to_int(rhs))
      end

      def to_int(text)
        raise TestError, "#{text}: integer expected" unless text.match?(/\A\s*[+-]?\d+\s*\z/)

        text.to_i
      end
    end
  end
end
