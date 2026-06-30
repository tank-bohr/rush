# typed: true
# frozen_string_literal: true

module Rush
  # Runs shell text command by command in the current shell — the engine shared
  # by `eval` and `.`. Reading and executing incrementally (via ProgramReader)
  # lets each command shape how the next is parsed: an `alias` or function
  # defined on one line takes effect on the following lines, and a syntax error
  # only stops the commands after it (the earlier ones have already run), exactly
  # as dash reads its input. The result starts at success and is updated by each
  # non-empty command, so empty input is status 0 while $? stays live for the
  # commands themselves (POSIX: eval and dot inherit the current $?).
  class SourceRunner
    extend T::Sig

    sig { params(executor: Executor, text: String).void }
    def initialize(executor, text)
      @executor = executor
      @lines = text.each_line.to_a
      @reader = ProgramReader.new(aliases: executor.state.aliases) { @lines.shift }
      @result = Status.success
    end

    sig { returns(Status) }
    def run
      loop { break if advance == :eof }
      @result
    end

    private

    # Read the next complete program and run it, returning it (or :eof) so `run`
    # knows when the input is exhausted.
    sig { returns(T.any(AST::List, Symbol)) }
    def advance
      program = @reader.next_program
      execute(T.cast(program, AST::List)) unless program == :eof
      program
    end

    sig { params(program: AST::List).void }
    def execute(program)
      @executor.run(program)
      @result = @executor.state.last_status unless program.empty?
    end
  end
end
