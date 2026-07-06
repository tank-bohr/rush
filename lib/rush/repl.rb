# typed: true
# frozen_string_literal: true

module Rush
  # A simple interactive read-eval-print loop over the shared ProgramReader: each
  # turn reads a complete command (continuation lines prompted with PS2) and runs
  # it against one persistent ShellState, so variables and functions survive
  # across lines. Prompts come from the PS1/PS2 shell variables (see Prompt) and
  # go to stderr; `exit` and end-of-input (Ctrl-D) end the loop; parse and
  # expansion errors are reported without ending the session. Line
  # editing/history and job control are deferred to later slices.
  class Repl < ProgramSession
    extend T::Sig

    private

    # A real syntax error reports and resumes the session; the next turn starts
    # fresh at PS1 (the reader discards the broken buffer per next_program call).
    sig { returns(T.any(AST::List, Symbol)) }
    def read_program
      super
    rescue ParseError => e
      recover(e)
      :error
    end

    sig { params(continuation: T::Boolean).returns(T.nilable(String)) }
    def next_line(continuation)
      prompt_line(continuation)
    end

    sig { params(continuation: T::Boolean).returns(T.nilable(String)) }
    def prompt_line(continuation)
      system.stderr.print(continuation ? prompt.continuation : prompt.primary)
      system.read_line
    end

    sig { returns(Prompt) }
    def prompt
      @prompt ||= T.let(Prompt.new(executor), T.nilable(Prompt))
    end

    sig { params(program: AST::List).void }
    def execute(program)
      super
    rescue ReturnSignal
      nil
    rescue ExpansionError, ReadonlyError, BuiltinError => e
      recover(e)
    end

    # POSIX 2.8.1: where a non-interactive shell would exit (status 2, per
    # Source#abort_with), the interactive shell reports the diagnostic,
    # publishes the same status as $?, and returns to the prompt.
    sig { params(error: StandardError).void }
    def recover(error)
      report(error)
      executor.state.record_status(Status.failure(2))
    end
  end
end
