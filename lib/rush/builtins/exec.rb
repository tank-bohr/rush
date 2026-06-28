# frozen_string_literal: true

module Rush
  module Builtins
    # `exec [command [arg ...]]` — with no command, make the redirections
    # permanent for the rest of the shell; with a command, replace the shell
    # process with it (applying the redirections first). A failed exec aborts the
    # shell with 127 (not found) or 126 (not executable), matching dash.
    class Exec < Base
      def call
        operands.empty? ? redirect_shell : replace_process
      end

      private

      def redirect_shell
        executor.replace_io(io)
        success
      end

      def replace_process
        executor.system.exec(environment.exported, operands, options)
      rescue Errno::ENOENT
        abort_exec('not found', 127)
      rescue Errno::EACCES
        abort_exec('Permission denied', 126)
      end

      def abort_exec(reason, code)
        stderr.puts("rush: #{operands.first}: #{reason}")
        raise ExitSignal, code
      end

      def options = io.to_spawn_options.merge(close_others: true)

      def environment = executor.state.environment
    end
  end
end
