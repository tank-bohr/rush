# frozen_string_literal: true

module Rush
  module Builtins
    # `eval [arg ...]` — join the arguments with spaces, parse the result as
    # shell input and run it in the current shell, returning its status. A
    # redirection on eval applies to the parsed commands (executor.with_io), and
    # exit/break/continue/return propagate to the enclosing context. A syntax
    # error in the input is reported with exit status 2.
    class Eval < Base
      def call
        executor.with_io(@io) { executor.run(parse(operands.join(' '))) }
      rescue ParseError => e
        report(e.message)
      end

      private

      def parse(text) = Parser.new(Lexer.new(text, aliases: executor.state.aliases)).parse

      def report(message)
        stderr.puts("rush: eval: #{message}")
        failure(2)
      end
    end
  end
end
