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

    # The subshell is a fresh top level: exit ends it with its code, a stray
    # break/continue/return is a no-op, and a fatal error (readonly, ${x:?}, ...)
    # aborts only the subshell — the parent shell carries on — without letting
    # the exception escape the fork.
    def run_body
      @executor.run(@body)
    rescue Error => e
      resolve(e)
    end

    private

    def resolve(error)
      return Status.new(error.code) if error.is_a?(ExitSignal)
      return @executor.state.last_status if control?(error)

      report_fatal(error)
    end

    def control?(error) = error.is_a?(LoopControl) || error.is_a?(ReturnSignal)

    def report_fatal(error)
      @executor.io.get(2).puts("rush: #{error.message}")
      Status.failure(2)
    end

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
