# frozen_string_literal: true

module Rush
  # Calls a shell function: bind the arguments as the positional parameters, run
  # the body in the current shell, and restore the previous positionals. `return`
  # unwinds to here as a ReturnSignal. (Dynamic `local` scope arrives in Phase 2.)
  class FunctionRunner
    def initialize(executor, body, args)
      @executor = executor
      @body = body
      @args = args
    end

    def call
      saved = @executor.state.positional
      @executor.state.positional = @args
      invoke
    ensure
      @executor.state.positional = saved
    end

    private

    def invoke
      @executor.run(@body)
      @executor.state.last_status
    rescue ReturnSignal => e
      Status.new(e.code)
    end
  end
end
