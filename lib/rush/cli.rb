# frozen_string_literal: true

module Rush
  # Entry point: parse argv, build the executor, run the requested source and
  # return the process exit code. Supports `-c command`, a batch program on
  # stdin, and an interactive REPL when invoked with no arguments on a terminal.
  # The program is read and executed command by command (see ProgramReader), so
  # earlier commands run — and flush their output — before a later syntax error,
  # and a fatal error fires the EXIT trap, both matching dash.
  class CLI
    def self.run(argv, system: SystemCalls.new) = new(argv, system).run

    def initialize(argv, system)
      @argv = argv
      @system = system
    end

    def run = repl? ? Repl.new(@system).run : run_source

    private

    def repl? = @argv.empty? && @system.tty?

    def run_source
      terminate(run_commands)
    rescue ExitSignal => e
      terminate(e.code)
    rescue ParseError, ExpansionError, ReadonlyError => e
      abort_with(e)
    end

    def run_commands
      queue = source.each_line.to_a
      reader = ProgramReader.new(aliases: executor.state.aliases) { queue.shift }
      loop { break unless continue?(reader) }
      executor.state.last_status.exitstatus
    end

    def continue?(reader)
      program = reader.next_program
      return false if program == :eof

      execute(program)
      true
    end

    def execute(program)
      executor.run(program)
    rescue LoopControl, ReturnSignal
      nil # break/continue/return outside a loop/function
    end

    # Fire the EXIT trap once the program (or an `exit`) has settled on a status.
    def terminate(code) = executor.run_exit_trap(code)

    # A fatal error (syntax/expansion/readonly): report it, publish 2 as $?, then
    # fire the EXIT trap (which may override the code via `exit`) — like dash.
    def abort_with(error)
      @system.stderr.puts("rush: #{error.message}")
      terminate(2)
    end

    def source
      return @argv[1].to_s if @argv.first == '-c'

      @system.stdin.read
    end

    def executor = @executor ||= Executor.new(system: @system, state: ShellState.new)
  end
end
