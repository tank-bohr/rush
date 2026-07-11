# typed: true
# frozen_string_literal: true

module Rush
  # Walks the AST by polymorphic dispatch (node.execute(self)) over shared shell
  # state, with all OS access funneled through the injected SystemCalls port. The
  # base IoTable, builtin registry, redirection registry and expander hang off it;
  # redirect cleanup, errexit state, signal and trap handling live in collaborators.
  class Executor
    extend T::Sig

    sig { returns(SystemCalls) }
    attr_reader :system

    sig { returns(ShellState) }
    attr_reader :state

    sig { returns(Builtins::Registry) }
    attr_reader :builtins

    sig { returns(Redirection::Registry) }
    attr_reader :redirections

    sig { returns(Expansion::Pipeline) }
    attr_reader :expander

    sig { returns(IoTable) }
    attr_reader :io

    sig { returns(Status) }
    attr_reader :cmd_sub_status

    sig { returns(TrapRunner) }
    attr_reader :trap_runner

    sig { returns(JobTable) }
    attr_reader :jobs

    sig { returns(RedirectScope) }
    attr_reader :redirect_scope

    sig { returns(ErrexitContext) }
    attr_reader :errexit

    sig { params(system: SystemCalls, state: ShellState, builtins: Builtins::Registry).void }
    def initialize(system:, state:, builtins: Builtins.default_registry)
      @system = system
      @state = state
      @builtins = builtins
      @redirections = Redirection.default_registry(@state.options)
      @expander = Expansion::Pipeline.new(self)
      @io = IoTable.standard(@system)
      @redirect_scope = RedirectScope.new(self)
      @errexit = ErrexitContext.new(@state)
      @trap_runner = TrapRunner.new(self)
      @jobs = JobTable.new(@system)
      @state.variables.seed_pwd(@system.pwd)
    end

    # The job-control policy over this executor: a stateless view, so it is
    # built on demand — the one durable bit (root shell or forked child) lives
    # with the job table, which already tracks subshell entry.
    sig { returns(JobControl) }
    def job_control
      JobControl.new(self)
    end

    # A redirect that fails at runtime (n>&m to a fd that is not open) leaves the
    # command unrun with status 2; the shell carries on (RedirectError).
    sig { params(node: AST::Node).returns(Status) }
    def run(node)
      @state.record_status(node.execute(self))
    rescue RedirectError
      @state.record_status(Status.new(2))
    end

    sig { params(node: AST::Node).returns(Status) }
    def run_async(node)
      @state.record_status(BackgroundRunner.new(self, node).call)
    end

    # Entering a forked child environment (subshell, pipeline stage, async
    # list, command substitution): caught traps reset (POSIX 2.11), and the
    # job table becomes a display copy — the duplicate environment keeps the
    # async-pid knowledge for jobs/jobs -p (POSIX 2.12, the seam that makes
    # `wait $(jobs -p)` work in the parent), while the parent's jobs are not
    # this environment's children: wait on them reports 127, a %id reports
    # No such job, and $! itself survives — which also switches job-control
    # machinery off (dash: root shell only).
    sig { void }
    def enter_subshell
      @trap_runner.reset_caught_for_subshell
      @jobs.enter_subshell
    end

    # Permanently rebind the base IoTable (the `exec` redirection-only form),
    # unlike with_io which restores afterwards.
    sig { params(table: IoTable).void }
    def replace_io(table)
      @io = table
    end

    sig { params(command: AST::SimpleCommand).returns(Status) }
    def run_simple(command)
      CommandRunner.new(self, command).call
    end

    # Run a compound command with its redirects bound for the whole body.
    sig { params(command: AST::Node, redirects: T::Array[AST::Redirect]).returns(Status) }
    def run_redirected(command, redirects)
      @redirect_scope.with_redirects(redirects) { |io| with_io(io) { run(command) } }
    end

    # The exit status of the last command substitution performed while a simple
    # command is being built. Reset to success at the start of each command so a
    # no-command-word command (only assignments/redirections) reports 0 unless a
    # substitution sets it (POSIX 2.9.1: such a command takes the status of the
    # last command substitution). Kept off last_status so a later $? in the same
    # command still sees the previous command's status, as dash does.
    sig { void }
    def reset_cmd_sub_status
      @cmd_sub_status = Status.success
    end

    sig { params(status: Status).void }
    def record_cmd_sub_status(status)
      @cmd_sub_status = status
    end

    # Run a block with a different base IoTable (command substitution / future
    # `exec`), restoring the previous one afterwards.
    sig do
      type_parameters(:U)
        .params(io: IoTable, blk: T.proc.returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def with_io(io, &blk)
      previous = @io
      @io = io
      yield
    ensure
      @io = previous
    end

    # Evaluate an if/while/until condition: run the command in a tested context
    # (so a failing condition never trips errexit) and report whether it succeeded.
    sig { params(command: AST::Node).returns(T::Boolean) }
    def succeeds?(command)
      @errexit.tested { run(command) }.success?
    end
  end
end
