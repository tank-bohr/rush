# typed: true
# frozen_string_literal: true

module Rush
  # Runs non-interactive shell source from `-c`, a script file, or stdin,
  # command by command. It owns the batch-mode error policy: fatal
  # syntax/expansion/builtin errors publish status 2, run the EXIT trap, and
  # stop the remaining input.
  class Source < ProgramSession
    extend T::Sig

    sig { params(invocation: Invocation, system: SystemCalls, state: ShellState, startup: T.nilable(Startup)).void }
    def initialize(invocation, system, state:, startup: nil)
      @source = T.let(invocation.source, String)
      super(system, state: state, startup: startup)
    end

    sig { returns(Integer) }
    def run
      super
    rescue Error => e
      handle_error(e)
    end

    private

    sig { params(_continuation: T::Boolean).returns(T.nilable(String)) }
    def next_line(_continuation)
      source_line.tap { |line| echo_verbose(line) }
    end

    # Under `set -v` (verbose) each input line is written to stderr as it is read,
    # before it runs, so a `set -v`/`set +v` toggles which later lines echo (POSIX).
    sig { params(line: T.nilable(String)).void }
    def echo_verbose(line)
      system.stderr.print(line) if line && executor.state.options.on?(:verbose)
    end

    sig { returns(T.nilable(String)) }
    def source_line
      source_lines.next
    rescue StopIteration
      nil
    end

    sig { returns(Enumerator) }
    def source_lines
      @source_lines ||= source.each_line
    end

    # A `return` not caught by a function or dot script acts like `exit` with
    # that code in a non-interactive shell (POSIX): re-raise as ExitSignal so it
    # settles the status and fires the EXIT trap. A stray break/continue no longer
    # reaches here — with no enclosing loop the builtin is a no-op.
    sig { params(program: AST::List).void }
    def execute(program)
      super
    rescue ReturnSignal => e
      raise ExitSignal, e.code
    end

    sig { params(error: Error).returns(Integer) }
    def handle_error(error)
      decision = ErrorPolicy.decision(:batch, error)
      return executor.trap_runner.run_exit_trap(130) if decision == :interrupt130
      return abort_with(error) if decision == :abort2

      raise error
    end

    # A fatal error (syntax/expansion/readonly): report it, publish 2 as $?, then
    # fire the EXIT trap (which may override the code via `exit`) — like dash.
    sig { params(error: StandardError).returns(Integer) }
    def abort_with(error)
      report(error)
      executor.trap_runner.run_exit_trap(2)
    end

    sig { returns(String) }
    attr_reader :source
  end
end
