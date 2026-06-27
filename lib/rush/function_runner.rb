# frozen_string_literal: true

module Rush
  # Calls a shell function: bind the arguments as the positional parameters, run
  # the body in the current shell, and restore the previous positionals. A scope
  # is opened so `local` declarations are undone on return. `return` unwinds to
  # here as a ReturnSignal.
  class FunctionRunner
    def initialize(executor, body, args)
      @executor = executor
      @body = body
      @args = args
    end

    def call
      @executor.state.begin_scope
      with_args { invoke }
    ensure
      @executor.state.end_scope
    end

    private

    def with_args
      saved = @executor.state.positional
      @executor.state.positional = @args
      yield
    ensure
      @executor.state.positional = saved
    end

    def invoke
      @executor.run(@body)
      @executor.state.last_status
    rescue ReturnSignal => e
      Status.new(e.code)
    end
  end
end
