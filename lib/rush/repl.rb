# frozen_string_literal: true

module Rush
  # A simple interactive read-eval-print loop. Each turn reads a line, appends
  # continuation lines until the buffer parses (IncompleteInput means "type
  # more", shown with PS2), then runs it against one persistent ShellState so
  # variables and functions survive across lines. Prompts go to stderr; `exit`
  # and end-of-input (Ctrl-D) end the loop; parse and expansion errors are
  # reported without ending the session. Line editing/history, PS1/PS2
  # customisation and job control are deferred to Phase 4.
  class Repl
    PS1 = '$ '
    PS2 = '> '

    def initialize(system)
      @system = system
      @executor = Executor.new(system: system, state: ShellState.new)
    end

    def run
      loop { break unless continue? }
      @executor.state.last_status.exitstatus
    rescue ExitSignal => e
      e.code
    end

    private

    def continue?
      program = read_complete
      return false if program == :eof

      run_program(program)
      true
    end

    def read_complete
      @buffer = +''
      loop do
        result = read_more
        return result if result
      end
    end

    # One read step: a parsed program or :eof to return, or nil to keep reading
    # (the line left a construct unfinished, or only reported an error).
    def read_more
      line = prompt_line
      return :eof if line.nil?

      result = attempt(@buffer << line)
      result unless result == :more
    end

    def prompt_line
      @system.stderr.print(@buffer.empty? ? PS1 : PS2)
      @system.read_line
    end

    def attempt(source)
      Parser.new(Lexer.new(source, interactive: true)).parse
    rescue IncompleteInput
      :more
    rescue ParseError => e
      recover(e)
    end

    def run_program(program)
      @executor.run(program)
    rescue LoopControl, ReturnSignal
      nil
    rescue ExpansionError, ReadonlyError => e
      report(e)
    end

    # A real syntax error: report it and discard the buffered input so the next
    # turn starts fresh at PS1 rather than re-parsing the broken line.
    def recover(error)
      report(error)
      @buffer = +''
      :more
    end

    def report(error) = @system.stderr.puts("rush: #{error.message}")
  end
end
