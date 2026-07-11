# typed: true
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
      # The operator tables map to lambdas, not method symbols, so each
      # primary carries its operand types past both checkers (the #: types
      # each lambda for Steep, the T.let the table for Sorbet).
      FILE_UNARY = T.let({
        '-e' => ->(files, val) { files.exist?(val) },          #: ^(SystemCalls, String) -> bool
        '-f' => ->(files, val) { files.file?(val) },           #: ^(SystemCalls, String) -> bool
        '-d' => ->(files, val) { files.directory?(val) },      #: ^(SystemCalls, String) -> bool
        '-r' => ->(files, val) { files.readable?(val) },       #: ^(SystemCalls, String) -> bool
        '-w' => ->(files, val) { files.writable?(val) },       #: ^(SystemCalls, String) -> bool
        '-x' => ->(files, val) { files.executable?(val) },     #: ^(SystemCalls, String) -> bool
        '-s' => ->(files, val) { files.file_nonempty?(val) },  #: ^(SystemCalls, String) -> bool
        '-h' => ->(files, val) { files.symlink?(val) },        #: ^(SystemCalls, String) -> bool
        '-L' => ->(files, val) { files.symlink?(val) }         #: ^(SystemCalls, String) -> bool
      }.freeze, T::Hash[String, T.proc.params(files: SystemCalls, val: String).returns(T::Boolean)])
      STRING = T.let({
        '=' => ->(lhs, rhs) { lhs == rhs },  #: ^(String, String) -> bool
        '!=' => ->(lhs, rhs) { lhs != rhs }  #: ^(String, String) -> bool
      }.freeze, T::Hash[String, T.proc.params(lhs: String, rhs: String).returns(T::Boolean)])
      INTEGER = T.let({
        '-eq' => ->(lhs, rhs) { lhs == rhs },  #: ^(Integer, Integer) -> bool
        '-ne' => ->(lhs, rhs) { lhs != rhs },  #: ^(Integer, Integer) -> bool
        '-gt' => ->(lhs, rhs) { lhs > rhs },   #: ^(Integer, Integer) -> bool
        '-ge' => ->(lhs, rhs) { lhs >= rhs },  #: ^(Integer, Integer) -> bool
        '-lt' => ->(lhs, rhs) { lhs < rhs },   #: ^(Integer, Integer) -> bool
        '-le' => ->(lhs, rhs) { lhs <= rhs }   #: ^(Integer, Integer) -> bool
      }.freeze, T::Hash[String, T.proc.params(lhs: Integer, rhs: Integer).returns(T::Boolean)])

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
          Integer(@text, 10) if valid?
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
        return negated?(args) if args.first == '!'
        return unwrap(args) if wrapped?(args)

        primary(args)
      end

      def negated?(args)
        !evaluate(args.drop(1))
      end

      def unwrap(args)
        evaluate(args[1...-1].to_a)
      end

      # A `( … )` wrapper drops to its contents at any length (dash recurses
      # through groupings POSIX leaves unspecified past four arguments); empty
      # `( )` peels to the no-argument test, which is false rather than an error.
      def wrapped?(args)
        args.size >= 2 && args.first == '(' && args.last == ')'
      end

      # The XCU argument-count table: zero arguments are false, one is the
      # non-empty test, two a unary primary, anything longer a syntax error.
      def primary(args)
        case args
        in [op, val] then unary(op, val)
        in [val] then !val.empty?
        else args.empty? ? false : bad
        end
      end

      def bad
        raise(TestError, 'syntax error')
      end

      # -n/-z are the two string unaries (XCU test); the rest ask the files.
      def unary(op, val)
        return !val.empty? if op == '-n'
        return val.empty? if op == '-z'
        return FILE_UNARY.fetch(op).call(@files, val) if FILE_UNARY.key?(op)

        raise TestError, "#{op}: unary operator expected"
      end

      def binary?(op)
        STRING.key?(op) || INTEGER.key?(op)
      end

      def binary(args)
        args => [lhs, op, rhs]
        return STRING.fetch(op).call(lhs, rhs) if STRING.key?(op)

        INTEGER.fetch(op).call(to_int(lhs), to_int(rhs))
      end

      def to_int(text)
        MaybeInteger.new(text).value || raise(TestError, "#{text}: integer expected")
      end
    end
  end
end
