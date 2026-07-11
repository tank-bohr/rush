# typed: true
# frozen_string_literal: true

module Rush
  # Shared command-by-command session over ProgramReader. Subclasses provide the
  # input source and tune error policy: batch source aborts on fatal errors,
  # while the REPL reports recoverable errors and keeps reading.
  class ProgramSession
    extend T::Sig

    sig { params(system: SystemCalls, state: ShellState, startup: T.nilable(Startup)).void }
    def initialize(system, state: ShellState.new(pids: ShellProcessIds.for(system)), startup: nil)
      @system = system
      @startup = startup
      @executor = Executor.new(system: system, state: state)
      InteractiveSignals.install(@executor) if state.options.on?(:interactive)
      @executor.job_control.startup
      @reader = ProgramReader.new(aliases: executor.state.aliases) { |continuation| next_line(continuation) }
    end

    sig { returns(Integer) }
    def run
      executor.trap_runner.run_exit_trap(session)
    rescue ExitSignal => e
      executor.trap_runner.run_exit_trap(e.code)
    end

    private

    sig { returns(SystemCalls) }
    attr_reader :system

    sig { returns(Executor) }
    attr_reader :executor

    sig { returns(ProgramReader) }
    attr_reader :reader

    sig { returns(Integer) }
    def session
      run_startup
      run_loop
      executor.state.last_status.exitstatus
    end

    # Login/ENV startup files run before the main input, inside the session's
    # error policy: batch subclasses let fatal errors abort (Source#run), the
    # REPL recovers (its override).
    sig { void }
    def run_startup
      @startup&.run(executor)
    end

    sig { void }
    def run_loop
      until (program = read_program) == :eof
        execute(T.cast(program, AST::List)) unless program == :error
      end
    end

    sig { returns(T.any(AST::List, Symbol)) }
    def read_program
      reader.next_program
    end

    sig { params(_continuation: T::Boolean).returns(T.nilable(String)) }
    def next_line(_continuation)
      # :nocov:
      raise NotImplementedError
      # :nocov:
    end

    sig { params(program: AST::List).void }
    def execute(program)
      executor.run(program)
    end

    sig { params(error: StandardError).void }
    def report(error)
      system.stderr.puts("rush: #{error.message}")
    end
  end
end
