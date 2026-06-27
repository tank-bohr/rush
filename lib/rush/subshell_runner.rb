# frozen_string_literal: true

module Rush
  # Runs `( list )` in a forked subshell so cd/variable changes never leak to the
  # parent. The child runs the body and exits with its status; the parent waits
  # and adopts that status. fork/exit! are the one irreducible wrapper (covered
  # by subprocess specs); the child-side `run_body` is tested directly.
  class SubshellRunner
    def initialize(executor, body)
      @executor = executor
      @body = body
    end

    def call
      pid = spawn_child
      Status.of(@executor.system.waitpid2(pid).last)
    end

    # The subshell is a fresh top level: exit ends it with its code, and a stray
    # break/continue/return is a no-op (as at the script top level).
    def run_body
      @executor.run(@body)
    rescue ExitSignal => e
      Status.new(e.code)
    rescue LoopControl, ReturnSignal
      @executor.state.last_status
    end

    private

    def spawn_child
      # :nocov:
      @executor.system.fork { run_child }
      # :nocov:
    end

    def run_child
      # :nocov:
      @executor.system.exit!(run_body.exitstatus)
      # :nocov:
    end
  end
end
