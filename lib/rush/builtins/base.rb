# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # Base for builtins. Subclasses implement #call returning a Status. Streams
    # come from the per-command IoTable so redirections apply to builtins too.
    class Base
      extend T::Sig

      # A signed decimal integer (surrounding blanks allowed); the caller's min
      # enforces whether negative or zero values are valid for this operand. dash
      # parses it into a C int, so a value past INT_MAX overflows and is rejected
      # like a non-numeric one.
      NUMERIC_OPERAND = /\A\s*[+-]?\d+\s*\z/
      INT_MAX = 2_147_483_647

      sig do
        params(executor: Executor, argv: T::Array[String], io: IoTable,
               environment: T.nilable(T::Hash[String, String])).void
      end
      def initialize(executor, argv, io, environment = nil)
        @executor = executor
        @argv = argv
        @io = io
        @environment = environment
      end

      sig { returns(Status) }
      def call
        raise NotImplementedError
      end

      private

      sig { returns(Executor) }
      attr_reader :executor

      sig { returns(T::Array[String]) }
      attr_reader :argv

      sig { returns(IoTable) }
      attr_reader :io

      # The exported environment assembled for this simple-command invocation,
      # including temporary prefix assignments. Most builtins do not consume it;
      # `command` forwards it when its nested target is external.
      sig { returns(T::Hash[String, String]) }
      def command_environment
        @environment || executor.state.variables.exported
      end

      sig { returns(T::Array[String]) }
      def operands
        argv.drop(1)
      end

      sig { returns(T.untyped) }
      def stdout
        io.get(1)
      end

      sig { returns(T.untyped) }
      def stderr
        io.get(2)
      end

      sig { returns(Status) }
      def success
        Status.success
      end

      sig { params(code: Integer).returns(Status) }
      def failure(code = 1)
        Status.failure(code)
      end

      # Parse a numeric operand for a special builtin: an exit code for
      # exit/return (min 0), or a loop level for break/continue (min 1). dash
      # rejects a non-numeric, too-small or out-of-range value with a
      # special-builtin error (which aborts a non-interactive shell).
      sig { params(text: String, min: Integer).returns(Integer) }
      def numeric_operand(text, min: 0)
        value = Integer(text, 10) if text.match?(NUMERIC_OPERAND)
        return T.must(value) if legal_operand?(value, min)

        raise BuiltinError, "#{argv.first}: Illegal number: #{text}"
      end

      sig { params(value: T.nilable(Integer), min: Integer).returns(T::Boolean) }
      def legal_operand?(value, min)
        !!value&.between?(min, INT_MAX)
      end
    end
  end
end
