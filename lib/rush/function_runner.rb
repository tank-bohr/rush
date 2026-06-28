# frozen_string_literal: true

module Rush
  # Calls a shell function: bind the arguments as the positional parameters, run
  # the body in the current shell, and restore the previous positionals. A scope
  # is opened so `local` declarations are undone on return. `return` unwinds to
  # here as a ReturnSignal.
  class FunctionRunner
    def initialize(executor, body, args)
      @executor = executor
      @state = executor.state
      @body = body
      @args = args
    end

    # A function body is a fresh loop scope: without_loops resets the depth so a
    # break/continue inside it cannot reach a loop in the caller (POSIX 2.9.5).
    def call
      @state.begin_scope
      @state.without_loops { with_args { invoke } }
    ensure
      @state.end_scope
    end

    private

    def with_args
      saved = @state.positional
      @state.positional = @args
      yield
    ensure
      @state.positional = saved
    end

    def invoke
      @executor.run(@body)
      @state.last_status
    rescue ReturnSignal => e
      Status.new(e.code)
    end
  end
end
