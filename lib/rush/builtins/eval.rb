# frozen_string_literal: true

module Rush
  module Builtins
    # `eval [arg ...]` — join the arguments with spaces and run the result in
    # the current shell, returning its status. The input is read command by
    # command (SourceRunner), so an `alias` or function defined by one command
    # shapes how the next is parsed. A redirection on eval applies to the parsed
    # commands (executor.with_io), and exit/break/continue/return all propagate
    # to the enclosing context. A syntax error is reported with exit status 2.
    class Eval < Base
      def call
        executor.with_io(@io) { SourceRunner.new(executor, operands.join(' ')).run }
      rescue ParseError => e
        report(e.message)
      end

      private

      def report(message)
        stderr.puts("rush: eval: #{message}")
        failure(2)
      end
    end
  end
end
