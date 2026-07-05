# typed: true
# frozen_string_literal: true

module Rush
  # A simple interactive read-eval-print loop over the shared ProgramReader: each
  # turn reads a complete command (continuation lines prompted with PS2) and runs
  # it against one persistent ShellState, so variables and functions survive
  # across lines. Prompts go to stderr; `exit` and end-of-input (Ctrl-D) end the
  # loop; parse and expansion errors are reported without ending the session.
  # Line editing/history, PS1/PS2 customisation and job control are deferred to
  # Phase 4.
  class Repl < ProgramSession
    extend T::Sig

    PS1 = '$ '
    PS2 = '> '

    private

    # A real syntax error reports and resumes the session; the next turn starts
    # fresh at PS1 (the reader discards the broken buffer per next_program call).
    sig { returns(T.any(AST::List, Symbol)) }
    def read_program
      super
    rescue ParseError => e
      report(e)
      :error
    end

    sig { params(continuation: T::Boolean).returns(T.nilable(String)) }
    def next_line(continuation)
      prompt_line(continuation)
    end

    sig { params(continuation: T::Boolean).returns(T.nilable(String)) }
    def prompt_line(continuation)
      system.stderr.print(continuation ? PS2 : PS1)
      system.read_line
    end

    sig { params(program: AST::List).void }
    def execute(program)
      super
    rescue ReturnSignal
      nil
    rescue ExpansionError, ReadonlyError, BuiltinError => e
      report(e)
    end
  end
end
