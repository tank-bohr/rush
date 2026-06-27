# frozen_string_literal: true

module Rush
  module Builtins
    # `. filename` — read the file and run it in the current shell, so its
    # functions and variables persist. Redirections apply to the file's commands
    # (executor.with_io) and exit/break/continue/return propagate to the caller.
    # PATH search for an unqualified name arrives with a later slice.
    class Dot < Base
      def call
        return usage if operands.empty?

        source(operands.first)
      rescue Errno::ENOENT
        report("#{operands.first}: No such file or directory")
      end

      private

      def source(path)
        text = executor.system.read_file(path)
        executor.with_io(@io) { executor.run(Parser.new(Lexer.new(text)).parse) }
      rescue ParseError => e
        report(e.message)
      end

      def usage
        stderr.puts('rush: .: filename argument required')
        failure(2)
      end

      def report(message)
        stderr.puts("rush: .: #{message}")
        failure
      end
    end
  end
end
