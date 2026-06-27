# frozen_string_literal: true

module Rush
  module Expansion
    # Runs $(...) / `...`: parse the body, run it in a forked subshell whose
    # stdout is a pipe, read everything the child writes, wait for it, and strip
    # trailing newlines (POSIX). spawn_child/run_child are the irreducible
    # fork/exit wrapper; `capture` (the child-side run) is tested directly.
    class CommandSubstitution
      def initialize(executor, source)
        @executor = executor
        @source = source
      end

      def call
        read, write = @executor.system.pipe
        pid = spawn_child(write)
        write.close
        strip(read_output(read, pid))
      end

      def capture(write)
        @executor.with_io(@executor.io.with(1, write)) { run_isolated }
      end

      private

      # The body runs in a fresh errexit context (a subshell): a `set -e` failure
      # ends only this substitution, leaving its status for the enclosing command.
      def run_isolated
        @executor.untested { @executor.run(parse) }
      rescue ExitSignal => e
        @executor.state.last_status = Status.new(e.code)
      end

      def read_output(read, pid)
        output = read.read
        read.close
        @executor.system.waitpid2(pid)
        output
      end

      def strip(output) = output.sub(/\n+\z/, '')

      def spawn_child(write)
        # :nocov:
        @executor.system.fork { run_child(write) }
        # :nocov:
      end

      def run_child(write)
        # :nocov:
        capture(write)
        @executor.system.exit!(@executor.state.last_status.exitstatus)
        # :nocov:
      end

      def parse = Parser.new(Lexer.new(@source)).parse
    end
  end
end
