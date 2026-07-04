# typed: true
# frozen_string_literal: true

module Rush
  # Runs `( list )` in a forked subshell so cd/variable changes never leak to the
  # parent. The child runs the body and exits with its status; the parent waits
  # and adopts that status. fork/exit! are the one irreducible wrapper (covered
  # by subprocess specs); the child-side `run_body` is tested directly.
  class SubshellRunner
    extend T::Sig

    sig { params(executor: Executor, body: AST::Node).void }
    def initialize(executor, body)
      @executor = executor
      @body = body
    end

    sig { returns(Status) }
    def call
      Status.of(@executor.system.waitpid2(spawn_child).last)
    end

    # The subshell is a fresh top level: exit (or an uncaught return) ends it
    # with that code, a stray break/continue is a no-op, and a fatal error
    # (readonly, ${x:?}, ...) aborts only the subshell — the parent shell carries
    # on — without letting the exception escape the fork.
    sig { returns(Status) }
    def run_body
      @executor.run(@body)
    rescue Error => e
      resolve(e)
    end

    private

    sig { params(error: Error).returns(Status) }
    def resolve(error)
      case error
      when ExitSignal, ReturnSignal then Status.new(error.code)
      when LoopControl then @executor.state.last_status
      else report_fatal(error)
      end
    end

    sig { params(error: Error).returns(Status) }
    def report_fatal(error)
      @executor.io.get(2).puts("rush: #{error.message}")
      Status.failure(2)
    end

    sig { returns(Integer) }
    def spawn_child
      # :nocov:
      @executor.system.fork { run_child } || 0
      # :nocov:
    end

    sig { returns(T.noreturn) }
    def run_child
      # :nocov:
      @executor.system.exit!(run_body.exitstatus)
      # :nocov:
    end
  end
end
