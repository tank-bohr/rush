# frozen_string_literal: true

module Rush
  # A simple interactive read-eval-print loop over the shared ProgramReader: each
  # turn reads a complete command (continuation lines prompted with PS2) and runs
  # it against one persistent ShellState, so variables and functions survive
  # across lines. Prompts go to stderr; `exit` and end-of-input (Ctrl-D) end the
  # loop; parse and expansion errors are reported without ending the session.
  # Line editing/history, PS1/PS2 customisation and job control are deferred to
  # Phase 4.
  class Repl
    PS1 = '$ '
    PS2 = '> '

    def initialize(system)
      @system = system
      @executor = Executor.new(system: system, state: ShellState.new)
      @reader = ProgramReader.new(aliases: @executor.state.aliases) { |c| prompt_line(c) }
    end

    def run
      terminate(session)
    rescue ExitSignal => e
      terminate(e.code)
    end

    private

    def session
      loop { break unless continue? }
      @executor.state.last_status.exitstatus
    end

    # The EXIT trap fires as the session ends, on Ctrl-D or `exit` alike.
    def terminate(code) = @executor.run_exit_trap(code)

    def continue?
      program = read_program
      return false if program == :eof

      run_program(program) unless program == :error
      true
    end

    # A real syntax error reports and resumes the session; the next turn starts
    # fresh at PS1 (the reader discards the broken buffer per next_program call).
    def read_program
      @reader.next_program
    rescue ParseError => e
      report(e)
      :error
    end

    def prompt_line(continuation)
      @system.stderr.print(continuation ? PS2 : PS1)
      @system.read_line
    end

    def run_program(program)
      @executor.run(program)
    rescue LoopControl, ReturnSignal
      nil
    rescue ExpansionError, ReadonlyError => e
      report(e)
    end

    def report(error) = @system.stderr.puts("rush: #{error.message}")
  end
end
