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

      sig { returns(Status) }
      def call
        return usage if operands.empty?

        formatter = PrintfFormatter.new(operands.drop(1))
        text, = formatter.render(operands.fetch(0))
        stdout.write(text)
        report(formatter.errors)
      end

      private

      sig { params(errors: Integer).returns(Status) }
      def report(errors)
        return success if errors.zero?

        errors.times { stderr.puts('rush: printf: expected numeric value') }
        failure
      end

      sig { returns(Status) }
      def usage
        stderr.puts('rush: printf: usage: printf format [arguments]')
        failure(2)
      end
    end
  end
end
