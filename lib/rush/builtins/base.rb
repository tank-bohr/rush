# frozen_string_literal: true

module Rush
  module Builtins
    # Base for builtins. Subclasses implement #call returning a Status. Streams
    # come from the per-command IoTable so redirections apply to builtins too.
    class Base
      # A non-negative decimal integer (optionally signed +, surrounding blanks);
      # the accepted form of an exit/return operand. dash parses it into a C int,
      # so a value past INT_MAX overflows and is rejected like a non-numeric one.
      NUMERIC_OPERAND = /\A\s*\+?\d+\s*\z/
      INT_MAX = 2_147_483_647

      def initialize(executor, argv, io)
        @executor = executor
        @argv = argv
        @io = io
      end

      def call = raise NotImplementedError

      private

      attr_reader :executor, :argv, :io

      def operands = argv.drop(1)

      def stdout = io.get(1)

      def stderr = io.get(2)

      def success = Status.success

      def failure(code = 1) = Status.failure(code)

      # Parse a numeric operand for a special builtin: an exit code for
      # exit/return (min 0), or a loop level for break/continue (min 1). dash
      # rejects a non-numeric, too-small or out-of-range value with a
      # special-builtin error (which aborts a non-interactive shell).
      def numeric_operand(text, min: 0)
        value = text.to_i
        return value if text.match?(NUMERIC_OPERAND) && value.between?(min, INT_MAX)

        raise BuiltinError, "#{argv.first}: Illegal number: #{text}"
      end
    end
  end
end
