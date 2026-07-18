# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # The operator vocabulary of `test`/`[`, shared by the argument-count
    # front end (TestExpr) and the recursive-descent grammar (TestGrammar).
    # The tables map to lambdas, not method symbols, so each primary carries
    # its operand types past both checkers. Each lambda gets its exact type at
    # construction — an outer table annotation cannot propagate inward to its
    # parameters. File primaries ask the SystemCalls port; -t parses its operand
    # as a file-descriptor number
    # first, rejecting non-numbers like dash's "Illegal number" (exit 2).
    module TestOperators
      extend T::Sig

      UnaryOp = T.type_alias do
        T.proc.params(files: SystemCalls, value: String).returns(T::Boolean)
      end
      StringOp = T.type_alias { T.proc.params(left: String, right: String).returns(T::Boolean) }
      IntegerOp = T.type_alias { T.proc.params(left: Integer, right: Integer).returns(T::Boolean) }

      UNARY = T.let({
        '-n' => T.let(
          begin
            ->(_files, value) { !value.empty? } #: unary_op
          end,
          UnaryOp
        ),
        '-z' => T.let(
          begin
            ->(_files, value) { value.empty? } #: unary_op
          end,
          UnaryOp
        ),
        '-t' => T.let(
          begin
            ->(files, value) { files.tty_fd?(fd_number(value)) } #: unary_op
          end,
          UnaryOp
        ),
        '-e' => T.let(
          begin
            ->(files, value) { files.exist?(value) } #: unary_op
          end,
          UnaryOp
        ),
        '-f' => T.let(
          begin
            ->(files, value) { files.file?(value) } #: unary_op
          end,
          UnaryOp
        ),
        '-d' => T.let(
          begin
            ->(files, value) { files.directory?(value) } #: unary_op
          end,
          UnaryOp
        ),
        '-r' => T.let(
          begin
            ->(files, value) { files.readable?(value) } #: unary_op
          end,
          UnaryOp
        ),
        '-w' => T.let(
          begin
            ->(files, value) { files.writable?(value) } #: unary_op
          end,
          UnaryOp
        ),
        '-x' => T.let(
          begin
            ->(files, value) { files.executable?(value) } #: unary_op
          end,
          UnaryOp
        ),
        '-s' => T.let(
          begin
            ->(files, value) { files.file_nonempty?(value) } #: unary_op
          end,
          UnaryOp
        ),
        '-h' => T.let(
          begin
            ->(files, value) { files.symlink?(value) } #: unary_op
          end,
          UnaryOp
        ),
        '-L' => T.let(
          begin
            ->(files, value) { files.symlink?(value) } #: unary_op
          end,
          UnaryOp
        ),
        '-p' => T.let(
          begin
            ->(files, value) { files.pipe?(value) } #: unary_op
          end,
          UnaryOp
        ),
        '-b' => T.let(
          begin
            ->(files, value) { files.blockdev?(value) } #: unary_op
          end,
          UnaryOp
        ),
        '-c' => T.let(
          begin
            ->(files, value) { files.chardev?(value) } #: unary_op
          end,
          UnaryOp
        ),
        '-S' => T.let(
          begin
            ->(files, value) { files.socket?(value) } #: unary_op
          end,
          UnaryOp
        ),
        '-g' => T.let(
          begin
            ->(files, value) { files.setgid?(value) } #: unary_op
          end,
          UnaryOp
        ),
        '-u' => T.let(
          begin
            ->(files, value) { files.setuid?(value) } #: unary_op
          end,
          UnaryOp
        )
      }.freeze, T::Hash[String, UnaryOp])
      STRING = T.let({
        '=' => T.let(
          begin
            ->(left, right) { left == right } #: string_op
          end,
          StringOp
        ),
        '!=' => T.let(
          begin
            ->(left, right) { left != right } #: string_op
          end,
          StringOp
        )
      }.freeze, T::Hash[String, StringOp])
      INTEGER = T.let({
        '-eq' => T.let(
          begin
            ->(left, right) { left == right } #: integer_op
          end,
          IntegerOp
        ),
        '-ne' => T.let(
          begin
            ->(left, right) { left != right } #: integer_op
          end,
          IntegerOp
        ),
        '-gt' => T.let(
          begin
            ->(left, right) { left > right } #: integer_op
          end,
          IntegerOp
        ),
        '-ge' => T.let(
          begin
            ->(left, right) { left >= right } #: integer_op
          end,
          IntegerOp
        ),
        '-lt' => T.let(
          begin
            ->(left, right) { left < right } #: integer_op
          end,
          IntegerOp
        ),
        '-le' => T.let(
          begin
            ->(left, right) { left <= right } #: integer_op
          end,
          IntegerOp
        )
      }.freeze, T::Hash[String, IntegerOp])

      # A string that may name an integer for the numeric primaries: #value is its
      # integer when it is a valid (optionally signed, blank-padded) decimal, else
      # nil. Underscores and 0x are rejected, matching dash's strtol-strictness.
      class MaybeInteger
        extend T::Sig

        PATTERN = /\A\s*[+-]?\d+\s*\z/

        sig { params(text: String).void }
        def initialize(text)
          @text = text
        end

        sig { returns(T::Boolean) }
        def valid?
          @text.match?(PATTERN)
        end

        sig { returns(T.nilable(Integer)) }
        def value
          Integer(@text, 10) if valid?
        end
      end

      sig { params(word: String).returns(T::Boolean) }
      def self.unary?(word)
        UNARY.key?(word)
      end

      sig { params(word: String).returns(T::Boolean) }
      def self.binary?(word)
        STRING.key?(word) || INTEGER.key?(word)
      end

      sig do
        params(op: String).returns(T.proc.params(files: SystemCalls, val: String).returns(T::Boolean))
      end
      def self.unary(op)
        UNARY.fetch(op)
      end

      sig { params(op: String, lhs: String, rhs: String).returns(T::Boolean) }
      def self.apply_binary(op, lhs, rhs)
        string = STRING[op]
        return string.call(lhs, rhs) if string

        INTEGER.fetch(op).call(to_int(lhs), to_int(rhs))
      end

      sig { params(text: String).returns(Integer) }
      def self.to_int(text)
        MaybeInteger.new(text).value || raise(TestError, "#{text}: integer expected")
      end

      sig { params(text: String).returns(Integer) }
      def self.fd_number(text)
        MaybeInteger.new(text).value || raise(TestError, "Illegal number: #{text}")
      end
    end
  end
end
