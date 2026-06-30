# typed: true
# frozen_string_literal: true

module Rush
  # Entry point: parse argv, build the executor, run the requested source and
  # return the process exit code. Supports `-c command`, a batch program on
  # stdin, and an interactive REPL when invoked with no arguments on a terminal.
  # The program is read and executed command by command (see ProgramReader), so
  # earlier commands run — and flush their output — before a later syntax error,
  # and a fatal error fires the EXIT trap, both matching dash.
  class CLI
    extend T::Sig

    sig { params(argv: T::Array[String], system: SystemCalls).returns(Integer) }
    def self.run(argv, system: SystemCalls.new)
      new(argv, system).run
    end

    sig { params(argv: T::Array[String], system: SystemCalls).void }
    def initialize(argv, system)
      @argv = argv
      @system = system
    end

    sig { returns(Integer) }
    def run
      repl? ? Repl.new(@system).run : run_source
    end

    private

    sig { returns(T::Boolean) }
    def repl?
      @argv.empty? && @system.tty?
    end

    sig { returns(Integer) }
    def run_source
      terminate(run_commands)
    rescue ExitSignal => e
      terminate(e.code)
    rescue ParseError, ExpansionError, ReadonlyError, BuiltinError => e
      abort_with(e)
    end

    sig { returns(Integer) }
    def run_commands
      queue = source.each_line.to_a
      reader = ProgramReader.new(aliases: executor.state.aliases) { echo_verbose(queue.shift) }
      loop { break unless continue?(reader) }
      executor.state.last_status.exitstatus
    end

    # Under `set -v` (verbose) each input line is written to stderr as it is read,
    # before it runs, so a `set -v`/`set +v` toggles which later lines echo (POSIX).
    sig { params(line: T.nilable(String)).returns(T.nilable(String)) }
    def echo_verbose(line)
      @system.stderr.print(line) if line && executor.state.options.on?(:verbose)
      line
    end

    sig { params(reader: ProgramReader).returns(T::Boolean) }
    def continue?(reader)
      program = reader.next_program
      return false if program == :eof

      execute(T.cast(program, AST::List))
      true
    end

    # A `return` not caught by a function or dot script acts like `exit` with
    # that code in a non-interactive shell (POSIX): re-raise as ExitSignal so it
    # settles the status and fires the EXIT trap. A stray break/continue no longer
    # reaches here — with no enclosing loop the builtin is a no-op.
    sig { params(program: AST::List).returns(Status) }
    def execute(program)
      executor.run(program)
    rescue ReturnSignal => e
      raise ExitSignal, e.code
    end

    # Fire the EXIT trap once the program (or an `exit`) has settled on a status.
    sig { params(code: Integer).returns(Integer) }
    def terminate(code)
      executor.trap_runner.run_exit_trap(code)
    end

    # A fatal error (syntax/expansion/readonly): report it, publish 2 as $?, then
    # fire the EXIT trap (which may override the code via `exit`) — like dash.
    sig { params(error: StandardError).returns(Integer) }
    def abort_with(error)
      @system.stderr.puts("rush: #{error.message}")
      terminate(2)
    end

    sig { returns(String) }
    def source
      return @argv[1].to_s if @argv.first == '-c'

      @system.stdin.read
    end

    sig { returns(Executor) }
    def executor
      @executor ||= Executor.new(system: @system, state: ShellState.new)
    end
  end
end
