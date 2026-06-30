# typed: true
# frozen_string_literal: true

module Rush
  # Runs `( list )` in a forked subshell so cd/variable changes never leak to the
  # parent. The child runs the body and exits with its status; the parent waits
  # and adopts that status. fork/exit! are the one irreducible wrapper (covered
  # by subprocess specs); the child-side `run_body` is tested directly.
  class SubshellRunner
    extend T::Sig

    sig { params(executor: T.untyped, body: T.untyped).void }
    def initialize(executor, body)
      @executor = executor
      @body = body
    end

    sig { returns(T.untyped) }
    def call
      pid = spawn_child
      Status.of(@executor.system.waitpid2(pid).last)
    end

    # The subshell is a fresh top level: exit (or an uncaught return) ends it
    # with that code, a stray break/continue is a no-op, and a fatal error
    # (readonly, ${x:?}, ...) aborts only the subshell — the parent shell carries
    # on — without letting the exception escape the fork.
    sig { returns(T.untyped) }
    def run_body
      @executor.run(@body)
    rescue Error => e
      resolve(e)
    end

    private

    sig { params(error: T.untyped).returns(T.untyped) }
    def resolve(error)
      return Status.new(error.code) if exit_like?(error)
      return @executor.state.last_status if error.is_a?(LoopControl)

      report_fatal(error)
    end

    # exit, and a `return` not caught by a function/dot, both end the subshell
    # with their code. A subshell inherits the loop scope (it is lexically inside
    # the loop), so a break/continue targeting a loop in the parent unwinds to
    # here and ends the subshell — the parent loop, a separate process, is
    # untouched. (With no enclosing loop the builtin no-ops and never raises.)
    sig { params(error: T.untyped).returns(T.untyped) }
    def exit_like?(error)
      error.is_a?(ExitSignal) || error.is_a?(ReturnSignal)
    end

    sig { params(error: T.untyped).returns(T.untyped) }
    def report_fatal(error)
      @executor.io.get(2).puts("rush: #{error.message}")
      Status.failure(2)
    end

    sig { returns(T.untyped) }
    def spawn_child
      # :nocov:
      @executor.system.fork { run_child }
      # :nocov:
    end

    sig { returns(T.untyped) }
    def run_child
      # :nocov:
      @executor.system.exit!(run_body.exitstatus)
      # :nocov:
    end
  end
end
