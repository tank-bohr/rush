# typed: true
# frozen_string_literal: true

module Rush
  # A simple interactive read-eval-print loop over the shared ProgramReader: each
  # turn reads a complete command (continuation lines prompted with PS2) and runs
  # it against one persistent ShellState, so variables and functions survive
  # across lines. Prompts come from the PS1/PS2 shell variables (see Prompt) and
  # go to stderr; `exit` and end-of-input (Ctrl-D) end the loop; errors and
  # SIGINT are reported without ending the session (see #survive). Line
  # editing/history and job control are deferred to later slices.
  class Repl < ProgramSession
    extend T::Sig

    private

    # A startup-file error (broken ~/.profile or ENV file) reports and keeps
    # the interactive session alive, where a batch shell would abort.
    sig { void }
    def run_startup
      survive(nil) { super }
    end

    # A real syntax error reports and resumes the session; the next turn starts
    # fresh at PS1 (the reader discards the broken buffer per next_program call).
    sig { returns(T.any(AST::List, Symbol)) }
    def read_program
      survive(:error) { super }
    end

    sig { params(continuation: T::Boolean).returns(T.nilable(String)) }
    def next_line(continuation)
      prompt_line(continuation)
    end

    sig { params(continuation: T::Boolean).returns(T.nilable(String)) }
    def prompt_line(continuation)
      text = continuation ? prompt.continuation : primary_prompt
      system.tty? ? edited_line(text) : plain_line(text)
    end

    sig { returns(String) }
    def primary_prompt
      executor.trap_runner.run_pending
      announce_jobs
      prompt.primary
    end

    # dash's cmdloop showjobs(SHOW_CHANGED): before each PS1 under monitor
    # mode, report every job whose state changed since it was last shown,
    # freeing the finished ones (probed: set +m silences the reports, and
    # the lines go to stderr with the prompts).
    sig { void }
    def announce_jobs
      jobs = executor.jobs
      jobs.announce_changed(system.stderr) if jobs.control.monitor?
    end

    # A terminal gets Reline: line editing and in-memory history, prompt drawn
    # by the editor. Reline strips the newline the reader needs to keep lines
    # apart, so it is restored here.
    sig { params(text: String).returns(T.nilable(String)) }
    def edited_line(text)
      line = system.edit_line(text)
      return unless line

      "#{line}\n"
    end

    sig { params(text: String).returns(T.nilable(String)) }
    def plain_line(text)
      system.stderr.print(text)
      system.read_line
    end

    sig { returns(Prompt) }
    def prompt
      @prompt ||= T.let(Prompt.new(executor), T.nilable(Prompt))
    end

    # Each interactive turn ticks the stopped-jobs exit warning (dash's
    # cmdloop decrements job_warning per iteration): a refused exit repeated
    # as the very next command goes through, anything later re-arms it.
    sig { params(program: AST::List).void }
    def execute(program)
      executor.jobs.control.tick_warning
      survive(nil) { super }
    end

    # The interactive survival policy: a recoverable error or a SIGINT reports,
    # publishes its status as $?, and hands `fallback` back so the session
    # carries on where a batch shell would abort.
    sig do
      type_parameters(:U)
        .params(fallback: T.type_parameter(:U), blk: T.proc.returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def survive(fallback, &blk)
      yield
    rescue Error => e
      recover(e)
      fallback
    end

    # POSIX 2.8.1: where a non-interactive shell would exit (status 2, per
    # Source#abort_with), the interactive shell reports the diagnostic,
    # publishes the same status as $?, and returns to the prompt. A SIGINT
    # publishes 130 instead, with a fresh line and no diagnostic.
    sig { params(error: Error).void }
    def recover(error)
      decision = ErrorPolicy.decision(:interactive, error)
      return interrupt if decision == :recover130
      return recover_operational(error) if decision == :recover2
      return if decision == :ignore

      raise error
    end

    sig { params(error: Error).void }
    def recover_operational(error)
      report(error)
      executor.state.record_status(Status.failure(2))
    end

    # ^C: a fresh line, $? = 130 (128+SIGINT), back to the prompt (dash
    # behaviour whether the signal arrived at the prompt or mid-command).
    sig { void }
    def interrupt
      system.stderr.puts
      executor.state.record_status(Status.failure(130))
    end
  end
end
