# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # `exec [command [arg ...]]` — with no command, make the redirections
    # permanent for the rest of the shell; with a command, replace the shell
    # process with it (applying the redirections first). A failed exec aborts the
    # shell with 127 (not found) or 126 (not executable), matching dash.
    class Exec < Base
      extend T::Sig

      sig { returns(Status) }
      def call
        operands.empty? ? redirect_shell : replace_process
      end

      private

      sig { returns(Status) }
      def redirect_shell
        executor.replace_io(io)
        success
      end

      sig { returns(T.noreturn) }
      def replace_process
        executor.system.exec(command_environment, operands, options)
      rescue Errno::ENOENT
        abort_exec('not found', 127)
      rescue Errno::EACCES
        abort_exec('Permission denied', 126)
      end

      sig { params(reason: String, code: Integer).returns(T.noreturn) }
      def abort_exec(reason, code)
        report_exec_error(reason)
        raise ExitSignal, code
      end

      sig { params(reason: String).void }
      def report_exec_error(reason)
        stderr.puts("rush: #{operands.first}: #{reason}")
      rescue Errno::EBADF
        nil
      end

      sig { returns(T::Hash[T.any(Integer, Symbol), T.untyped]) }
      def options
        io.to_spawn_options.merge(close_others: true)
      end
    end
  end
end
