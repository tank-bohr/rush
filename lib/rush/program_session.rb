# typed: true
# frozen_string_literal: true

module Rush
  # Shared command-by-command session over ProgramReader. Subclasses provide the
  # input source and tune error policy: batch source aborts on fatal errors,
  # while the REPL reports recoverable errors and keeps reading.
  class ProgramSession
    extend T::Sig

    sig { params(system: SystemCalls).void }
    def initialize(system)
      @system = system
      @executor = Executor.new(system: system, state: ShellState.new)
      @reader = ProgramReader.new(aliases: executor.state.aliases) { |continuation| next_line(continuation) }
    end

    sig { returns(Integer) }
    def run
      executor.run_exit_trap(session)
    rescue ExitSignal => e
      executor.run_exit_trap(e.code)
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
      run_loop
      executor.exitstatus
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
