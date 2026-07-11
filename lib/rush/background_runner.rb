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
      pid = @executor.job_control.launch_background { run_child }
      @executor.state.record_background_pid(pid)
      @executor.jobs.record(pid, text: @executor.job_control.job_text(@body))
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
    # with SIGINT/SIGQUIT ignored. Both apply ONLY without job control — under
    # set -m the job sits in its own process group, so POSIX (and dash,
    # probed) leave stdin and SIGINT alone; monitored? is read before
    # enter_subshell switches the machinery off for this child. The subshell
    # entry (trap reset + job-table clear) must run first — an interactive
    # session's base handlers reinstall OS defaults as they drop, which would
    # undo the ignores (the repeat inside SubshellRunner#run_body is then a
    # no-op). The ignores are a real SIG_IGN, kept off the trap table: they
    # survive exec and nested subshells, while `trap` overrides them and
    # `trap - INT` restores the OS default (dash-verified).
    sig { void }
    def isolate
      monitored = @executor.job_control.monitored?
      @executor.enter_subshell
      return if monitored

      %w[INT QUIT].each { |name| @executor.system.trap_signal(name, 'IGNORE') { nil } }
      @executor.replace_io(@executor.io.with(0, @executor.system.open_file(File::NULL, 'r')))
    end

    sig { returns(T.noreturn) }
    def run_child
      # :nocov:
      @executor.system.exit!(run_body.exitstatus)
      # :nocov:
    end
  end
end
