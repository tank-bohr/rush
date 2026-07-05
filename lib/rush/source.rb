# typed: true
# frozen_string_literal: true

module Rush
  # Runs non-interactive shell source from `-c` or stdin, command by command.
  # It owns the batch-mode error policy: fatal syntax/expansion/builtin errors
  # publish status 2, run the EXIT trap, and stop the remaining input.
  class Source
    extend T::Sig

    sig { params(argv: T::Array[String], system: SystemCalls).void }
    def initialize(argv, system)
      @argv = argv
      @system = system
    end

    sig { returns(Integer) }
    def run
      terminate(run_commands)
    rescue ExitSignal => e
      terminate(e.code)
    rescue ParseError, ExpansionError, ReadonlyError, BuiltinError => e
      abort_with(e)
    end

    private

    sig { returns(Integer) }
    def run_commands
      run_loop(program_reader)
      executor.state.last_status.exitstatus
    end

    sig { returns(ProgramReader) }
    def program_reader
      queue = source.each_line
      ProgramReader.new(aliases: executor.state.aliases) { next_line(queue).tap { |line| echo_verbose(line) } }
    end

    # Under `set -v` (verbose) each input line is written to stderr as it is read,
    # before it runs, so a `set -v`/`set +v` toggles which later lines echo (POSIX).
    sig { params(line: T.nilable(String)).void }
    def echo_verbose(line)
      @system.stderr.print(line) if line && executor.state.options.on?(:verbose)
    end

    sig { params(lines: Enumerator).returns(T.nilable(String)) }
    def next_line(lines)
      lines.next
    rescue StopIteration
      nil
    end

    sig { params(reader: ProgramReader).void }
    def run_loop(reader)
      until (program = reader.next_program) == :eof
        execute(T.cast(program, AST::List))
      end
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
      if @argv.first == '-c'
        @argv.fetch(1, '')
      else
        @system.stdin.read
      end
    end

    sig { returns(Executor) }
    def executor
      @executor ||= Executor.new(system: @system, state: ShellState.new)
    end
  end
end
