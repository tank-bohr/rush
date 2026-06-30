# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `printf format [arg ...]` — write the arguments under the control of the
    # format, which is reused until the arguments are exhausted. Writes no
    # trailing newline of its own. A present non-numeric argument to a numeric
    # conversion is reported and treated as 0 (exit status 1).
    class Printf < Base
      extend T::Sig

      sig { returns(T.untyped) }
      def call
        return usage if operands.empty?

        text, ok = PrintfFormatter.new(operands.drop(1)).render(operands.first)
        stdout.write(text)
        report(ok)
      end

      private

      sig { params(valid: T.untyped).returns(T.untyped) }
      def report(valid)
        stderr.puts('rush: printf: expected numeric value') unless valid
        valid ? success : failure
      end

      sig { returns(T.untyped) }
      def usage
        stderr.puts('rush: printf: usage: printf format [arguments]')
        failure(2)
      end
    end
  end
end
