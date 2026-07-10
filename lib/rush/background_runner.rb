# typed: true
# frozen_string_literal: true

module Rush
  # Runs an asynchronous list entry in a forked subshell. The parent records
  # the child pid for $! and in the job table (where the wait builtin finds
  # it) and immediately returns success (launch semantics); the child resolves
  # shell-control exceptions to an exit status like a subshell.
  class BackgroundRunner
    extend T::Sig

    sig { params(executor: Executor, body: AST::Node).void }
    def initialize(executor, body)
      @executor = executor
      @body = body
    end

    sig { returns(Status) }
    def call
      pid = spawn_child
      @executor.state.record_background_pid(pid)
      @executor.jobs.record(pid)
      Status.success
    end

    sig { returns(Status) }
    def run_body
      SubshellRunner.new(@executor, @body).run_body
    end

    private

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
