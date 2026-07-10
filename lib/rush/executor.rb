# typed: true
# frozen_string_literal: true

module Rush
  # Walks the AST by polymorphic dispatch (node.execute(self)) over shared shell
  # state, with all OS access funneled through the injected SystemCalls port. The
  # base IoTable, builtin registry, redirection registry and expander hang off it;
  # redirect cleanup, errexit state, signal and trap handling live in collaborators.
  class Executor # rubocop:disable Metrics/ClassLength
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

    sig { returns(Integer) }
    def exitstatus
      @state.last_status.exitstatus
    end

    sig { params(code: Integer).returns(Integer) }
    def run_exit_trap(code)
      @trap_runner.run_exit_trap(code)
    end

    # Entering a forked child environment (subshell, pipeline stage, async
    # list, command substitution): caught traps reset (POSIX 2.11), and the
    # job table empties — the parent's jobs are not this environment's
    # children (POSIX 2.12: wait on them reports 127, a %id reports No such
    # job; the value of $! itself survives) — which also switches job-control
    # machinery off (dash: root shell only). dash-verified on every forked
    # shape.
    sig { void }
    def enter_subshell
      @trap_runner.reset_caught_for_subshell
      @jobs.clear_for_subshell
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

    # Apply the redirects on top of a base IoTable, yield the result, then
    # flush+close the files those redirects opened (POSIX: a later command in the
    # same shell sees the data). Only the streams this command opened are closed —
    # the diff against the base leaves inherited streams and pipe ends untouched.
    # Exception: redirect-only `exec` commits the table as the shell's base
    # (replace_io), so it now equals @io — leave those files open so they persist
    # for the rest of the shell rather than closing them out from under it.
    sig do
      type_parameters(:U)
        .params(redirects: T::Array[AST::Redirect], base: IoTable,
                blk: T.proc.params(io: IoTable).returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def with_redirects(redirects, base = @io, &blk)
      @redirect_scope.with_redirects(redirects, base, &blk)
    end

    # Run a compound command with its redirects bound for the whole body.
    sig { params(command: AST::Node, redirects: T::Array[AST::Redirect]).returns(Status) }
    def run_redirected(command, redirects)
      with_redirects(redirects) { |io| with_io(io) { run(command) } }
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

    # Run a block in a "tested" context (errexit suppressed): the condition of
    # if/while/until, the non-final part of an && / || list, a negated pipeline,
    # and an async (&) command. `untested` is the inverse — command substitution
    # starts a fresh errexit context regardless of the caller's. Both restore on
    # exit, so the flag follows the call tree.
    sig do
      type_parameters(:U)
        .params(blk: T.proc.returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def tested(&blk)
      @errexit.tested(&blk)
    end

    sig do
      type_parameters(:U)
        .params(blk: T.proc.returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def untested(&blk)
      @errexit.untested(&blk)
    end

    # Evaluate an if/while/until condition: run the command in a tested context
    # (so a failing condition never trips errexit) and report whether it succeeded.
    sig { params(command: AST::Node).returns(T::Boolean) }
    def succeeds?(command)
      tested { run(command) }.success?
    end

    # The errexit leaf check (POSIX 2.8.1): under `set -e`, a command failing
    # outside a tested context aborts the shell with that status.
    sig { params(status: Status).returns(Status) }
    def exit_on_error(status)
      @errexit.exit_on_error(status)
    end
  end
end
