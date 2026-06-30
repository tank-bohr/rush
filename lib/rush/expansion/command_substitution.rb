# typed: true
# frozen_string_literal: true

module Rush
  module Expansion
    # Runs $(...) / `...`: parse the body, run it in a forked subshell whose
    # stdout is a pipe, read everything the child writes, wait for it, and strip
    # trailing newlines (POSIX). spawn_child/run_child are the irreducible
    # fork/exit wrapper; `capture` (the child-side run) is tested directly.
    class CommandSubstitution
      extend T::Sig

      sig { params(executor: T.untyped, source: T.untyped).void }
      def initialize(executor, source)
        @executor = executor
        @source = source
      end

      sig { returns(T.untyped) }
      def expand
        read, write = @executor.system.pipe
        pid = spawn_child(write)
        write.close
        strip(read_output(read, pid))
      end

      sig { params(write: T.untyped).returns(T.untyped) }
      def capture(write)
        @executor.with_io(@executor.io.with(1, write)) { run_isolated }
      end

      private

      # The body runs in a fresh errexit context (a subshell): a `set -e` failure
      # ends only this substitution, leaving its status for the enclosing command.
      # exit, and an uncaught return, both end the substitution with their code.
      sig { returns(T.untyped) }
      def run_isolated
        @executor.untested { @executor.run(parse) }
      rescue ExitSignal, ReturnSignal => e
        @executor.state.record_status(Status.new(e.code))
      end

      sig { params(read: T.untyped, pid: T.untyped).returns(T.untyped) }
      def read_output(read, pid)
        output = read.read
        read.close
        _pid, status = @executor.system.waitpid2(pid)
        @executor.record_cmd_sub_status(Status.of(status))
        output
      end

      sig { params(output: T.untyped).returns(T.untyped) }
      def strip(output)
        output.sub(/\n+\z/, '')
      end

      sig { params(write: T.untyped).returns(T.untyped) }
      def spawn_child(write)
        # :nocov:
        @executor.system.fork { run_child(write) }
        # :nocov:
      end

      sig { params(write: T.untyped).returns(T.untyped) }
      def run_child(write)
        # :nocov:
        capture(write)
        @executor.system.exit!(@executor.state.last_status.exitstatus)
        # :nocov:
      end

      sig { returns(T.untyped) }
      def parse
        Parser.new(Lexer.new(@source, aliases: @executor.state.aliases)).parse
      end
    end
  end
end
