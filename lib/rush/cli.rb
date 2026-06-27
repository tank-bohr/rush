# frozen_string_literal: true

module Rush
  # Entry point: parse argv, build the executor, run the requested source and
  # return the process exit code. Phase 0 supports `-c command` and stdin; a
  # script-file argument, option flags and the REPL arrive in later phases.
  class CLI
    def self.run(argv, system: SystemCalls.new) = new(argv, system).run

    def initialize(argv, system)
      @argv = argv
      @system = system
    end

    def run
      execute(source)
    rescue ExitSignal => e
      e.code
    rescue ParseError, ExpansionError => e
      report_error(e)
    end

    private

    def source
      return @argv[1].to_s if @argv.first == '-c'

      @system.stdin.read
    end

    def execute(text)
      executor = Executor.new(system: @system, state: ShellState.new)
      executor.run(parse(text))
      executor.state.last_status.exitstatus
    rescue LoopControl, ReturnSignal
      executor.state.last_status.exitstatus # break/continue/return outside a loop/function
    end

    def parse(text) = Parser.new(Lexer.new(text)).parse

    def report_error(error)
      @system.stderr.puts("rush: #{error.message}")
      2
    end
  end
end
