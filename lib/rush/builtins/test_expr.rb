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

      # A string that may name an integer for the numeric primaries: #value is its
      # integer when it is a valid (optionally signed, blank-padded) decimal, else
      # nil. Underscores and 0x are rejected, matching dash's strtol-strictness.
      class MaybeInteger
        PATTERN = /\A\s*[+-]?\d+\s*\z/

        def initialize(text)
          @text = text
        end

        def valid?
          @text.match?(PATTERN)
        end

        def value
          @text.to_i if valid?
        end
      end

      def initialize(args, files)
        @args = args
        @files = files
      end

      def true?
        evaluate(@args)
      end

      private

      def evaluate(args)
        return binary(args) if args.size == 3 && binary?(args[1])
        return !evaluate(args.drop(1)) if args.first == '!'
        return evaluate(args[1...-1].to_a) if wrapped?(args)

        primary(args)
      end

      # A `( … )` wrapper drops to its contents at any length (dash recurses
      # through groupings POSIX leaves unspecified past four arguments); empty
      # `( )` peels to the no-argument test, which is false rather than an error.
      def wrapped?(args)
        args.size >= 2 && args.first == '(' && args.last == ')'
      end

      def primary(args)
        send(PRIMARY.fetch(args.size, :bad), *args)
      end

      def none?
        false
      end

      def bad(*)
        raise(TestError, 'syntax error')
      end

      def unary(op, val)
        return send(STRING_UNARY.fetch(op), val) if STRING_UNARY.key?(op)
        return @files.public_send(FILE_UNARY.fetch(op), val) if FILE_UNARY.key?(op)

        raise TestError, "#{op}: unary operator expected"
      end

      def nonempty?(val)
        !val.empty?
      end

      def empty?(val)
        val.empty?
      end

      def binary?(op)
        STRING.key?(op) || INTEGER.key?(op)
      end

      def binary(args)
        lhs, op, rhs = args
        op = op.to_s
        return lhs.public_send(STRING.fetch(op), rhs) if STRING.key?(op)

        to_int(lhs).public_send(INTEGER.fetch(op), to_int(rhs))
      end

      def to_int(text)
        MaybeInteger.new(text.to_s).value || raise(TestError, "#{text}: integer expected")
      end
    end
  end
end
