# typed: true
# frozen_string_literal: true

module Rush
  # Entry point: dispatch to the interactive REPL or the non-interactive source
  # runner and return the process exit code. Supports `-c command`, a batch
  # program on stdin, and an interactive REPL when invoked with no arguments on a
  # terminal.
  class CLI
    extend T::Sig

    sig { params(argv: T::Array[String], system: SystemCalls).returns(Integer) }
    def self.run(argv, system: SystemCalls.new)
      new(argv, system).run
    end

    sig { params(argv: T::Array[String], system: SystemCalls).void }
    def initialize(argv, system)
      @argv = argv
      @system = system
    end

    sig { returns(Integer) }
    def run
      repl? ? Repl.new(@system).run : Source.new(@argv, @system).run
    end

    private

    sig { returns(T::Boolean) }
    def repl?
      @argv.empty? && @system.tty?
    end
  end
end
