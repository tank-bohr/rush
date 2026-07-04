# typed: true
# frozen_string_literal: true

module Rush
  # Calls a shell function: bind the arguments as the positional parameters, run
  # the body in the current shell, and restore the previous positionals. A scope
  # is opened so `local` declarations are undone on return. `return` unwinds to
  # here as a ReturnSignal.
  class FunctionRunner
    extend T::Sig

    sig { params(executor: Executor, body: AST::Node, args: T::Array[String]).void }
    def initialize(executor, body, args)
      @executor = executor
      @state = executor.state
      @body = body
      @args = args
    end

    # A function body runs inside a ShellState-owned function frame: locals are
    # scoped, positionals are rebound, and loop depth is reset (POSIX 2.9.5).
    sig { returns(Status) }
    def call
      @state.with_function_frame(@args) { invoke }
    end

    private

    sig { returns(Status) }
    def invoke
      @executor.run(@body)
      @state.last_status
    rescue ReturnSignal => e
      Status.new(e.code)
    end
  end
end
