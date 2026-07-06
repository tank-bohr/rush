# typed: true
# frozen_string_literal: true

module Rush
  # Entry point: parse the invocation, run the session it implies (interactive
  # REPL or non-interactive source), and return the process exit code. A
  # malformed command line — unknown option, missing -c/-o argument, unreadable
  # script file — reports on stderr and exits 2, like dash.
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
      Invocation.new(@argv, @system).session.run
    rescue InvocationError => e
      @system.stderr.puts("rush: #{e.message}")
      2
    end
  end
end
