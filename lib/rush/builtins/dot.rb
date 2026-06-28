# frozen_string_literal: true

module Rush
  module Builtins
    # `. filename` — read the file and run it in the current shell, so its
    # functions and variables persist. The file is read command by command
    # (SourceRunner), so an alias or function it defines shapes its own later
    # lines. Redirections apply to the file's commands (executor.with_io);
    # exit/break/continue propagate to the caller, but `return` is bounded to the
    # dot script — it stops the file and becomes the `.` command's status (POSIX
    # 2.14), unlike eval. A missing file or a syntax error is a special-builtin
    # error that aborts a non-interactive shell with status 2 (BuiltinError); a
    # missing operand is a plain usage error that does not abort. PATH search for
    # an unqualified name arrives later.
    class Dot < Base
      def call
        return usage if operands.empty?

        source(operands.first)
      rescue Errno::ENOENT
        raise BuiltinError, ".: #{operands.first}: No such file or directory"
      end

      private

      def source(path)
        text = executor.system.read_file(path)
        executor.with_io(io) { run_text(text) }
      rescue ParseError => e
        raise BuiltinError, ".: #{e.message}"
      end

      def run_text(text)
        SourceRunner.new(executor, text).run
      rescue ReturnSignal => e
        Status.new(e.code)
      end

      def usage
        stderr.puts('rush: .: filename argument required')
        failure(2)
      end
    end
  end
end
