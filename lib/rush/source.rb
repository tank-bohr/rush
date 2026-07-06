# typed: true
# frozen_string_literal: true

module Rush
  # Parsed non-interactive input source plus the shell parameters it implies.
  SourceConfig = Data.define(:source, :name, :positionals) do
    extend T::Sig

    sig { params(argv: T::Array[String], system: SystemCalls).returns(SourceConfig) }
    def self.for(argv, system)
      argv.first == '-c' ? command(argv) : stdin(system)
    end

    sig { params(argv: T::Array[String]).returns(SourceConfig) }
    def self.command(argv)
      new(argv.fetch(1, ''), argv.fetch(2, 'rush'), argv.drop(3))
    end

    sig { params(system: SystemCalls).returns(SourceConfig) }
    def self.stdin(system)
      new(system.stdin.read, 'rush', [])
    end
  end

  # Runs non-interactive shell source from `-c` or stdin, command by command.
  # It owns the batch-mode error policy: fatal syntax/expansion/builtin errors
  # publish status 2, run the EXIT trap, and stop the remaining input.
  class Source < ProgramSession
    extend T::Sig

    sig { params(argv: T::Array[String], system: SystemCalls).void }
    def initialize(argv, system)
      @config = SourceConfig.for(argv, system)
      super(system, state: shell_state(system))
    end

    sig { returns(Integer) }
    def run
      super
    rescue ParseError, ExpansionError, ReadonlyError, BuiltinError => e
      abort_with(e)
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

    # A fatal error (syntax/expansion/readonly): report it, publish 2 as $?, then
    # fire the EXIT trap (which may override the code via `exit`) — like dash.
    sig { params(error: StandardError).returns(Integer) }
    def abort_with(error)
      report(error)
      executor.run_exit_trap(2)
    end

    sig { params(system: SystemCalls).returns(ShellState) }
    def shell_state(system)
      ShellState.new(name: @config.name, positional: @config.positionals, pids: ShellProcessIds.for(system))
    end

    sig { returns(String) }
    def source
      @config.source
    end
  end
end
