# typed: true
# frozen_string_literal: true

module Rush
  # Runs an asynchronous list entry in a forked subshell. The parent records
  # the child pid for $! and in the job table (where the wait builtin finds
  # it) and immediately returns success (launch semantics); the child
  # isolates itself per POSIX (stdin from /dev/null, SIGINT/SIGQUIT ignored)
  # and resolves shell-control exceptions to an exit status like a subshell.
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
      isolate
      SubshellRunner.new(@executor, @body).run_body
    end

    private

    # POSIX 2.9.3.1 / 2.11 with job control disabled: an async child reads
    # stdin from /dev/null (its own redirections may rebind it) and starts
    # with SIGINT/SIGQUIT ignored. The subshell trap reset must run first —
    # an interactive session's base handlers reinstall OS defaults as they
    # drop, which would undo the ignores (the repeat reset inside
    # SubshellRunner#run_body is then a no-op). The ignores are a real
    # SIG_IGN, kept off the trap table: they survive exec and nested
    # subshells, while `trap` overrides them and `trap - INT` restores the
    # OS default (dash-verified).
    sig { void }
    def isolate
      @executor.reset_caught_traps_for_subshell
      %w[INT QUIT].each { |name| @executor.system.trap_signal(name, 'IGNORE') { nil } }
      @executor.replace_io(@executor.io.with(0, @executor.system.open_file(File::NULL, 'r')))
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
