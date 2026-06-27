# frozen_string_literal: true

module Rush
  # Entry point: parse argv, build the executor, run the requested source and
  # return the process exit code. Supports `-c command`, a batch program on
  # stdin, and an interactive REPL when invoked with no arguments on a terminal.
  # A script-file argument and option flags arrive in later phases.
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
      terminate(execute)
    rescue ExitSignal => e
      terminate(e.code)
    rescue ParseError, ExpansionError, ReadonlyError => e
      report_error(e)
    end

    # Fire the EXIT trap once the program (or an `exit`) has settled on a status.
    def terminate(code) = executor.run_exit_trap(code)

    def source
      return @argv[1].to_s if @argv.first == '-c'

      @system.stdin.read
    end

    def execute
      executor.run(parse(source))
      executor.state.last_status.exitstatus
    rescue LoopControl, ReturnSignal
      executor.state.last_status.exitstatus # break/continue/return outside a loop/function
    end

    def executor = @executor ||= Executor.new(system: @system, state: ShellState.new)

    def parse(text) = Parser.new(Lexer.new(text)).parse

    def report_error(error)
      @system.stderr.puts("rush: #{error.message}")
      2
    end
  end
end
