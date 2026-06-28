# frozen_string_literal: true

module Rush
  # Walks the AST by polymorphic dispatch (node.execute(self)) over shared shell
  # state, with all OS access funneled through the injected SystemCalls port. The
  # base IoTable, builtin registry, redirection registry and expander hang off it;
  # signal and trap handling live in the TrapRunner it owns.
  class Executor
    attr_reader :system, :state, :builtins, :redirections, :expander, :io, :cmd_sub_status, :trap_runner

    def initialize(system:, state:, builtins: Builtins.default_registry)
      @system = system
      @state = state
      @builtins = builtins
      @redirections = Redirection.default_registry
      @expander = Expansion::Pipeline.new(self)
      @io = IoTable.standard(@system)
      @tested = false
      @trap_runner = TrapRunner.new(self)
      @state.scope.seed_pwd(@system.pwd)
    end

    # A redirect that fails at runtime (n>&m to a fd that is not open) leaves the
    # command unrun with status 2; the shell carries on (RedirectError).
    def run(node)
      @state.record_status(node.execute(self))
    rescue RedirectError
      @state.record_status(Status.new(2))
    end

    # Permanently rebind the base IoTable (the `exec` redirection-only form),
    # unlike with_io which restores afterwards.
    def replace_io(table)
      @io = table
    end

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
    def with_redirects(redirects, base = @io)
      io = redirects.reduce(base) { |acc, redirect| redirect_into(redirect, acc) }
      yield io
    ensure
      io&.close_opened_over(base, system) unless io.equal?(@io)
    end

    # Run a compound command with its redirects bound for the whole body.
    def run_redirected(command, redirects)
      with_redirects(redirects) { |io| with_io(io) { run(command) } }
    end

    # The exit status of the last command substitution performed while a simple
    # command is being built. Reset to success at the start of each command so a
    # no-command-word command (only assignments/redirections) reports 0 unless a
    # substitution sets it (POSIX 2.9.1: such a command takes the status of the
    # last command substitution). Kept off last_status so a later $? in the same
    # command still sees the previous command's status, as dash does.
    def reset_cmd_sub_status
      @cmd_sub_status = Status.success
    end

    def record_cmd_sub_status(status)
      @cmd_sub_status = status
    end

    # Run a block with a different base IoTable (command substitution / future
    # `exec`), restoring the previous one afterwards.
    def with_io(io)
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
    def tested(&)
      scoped_tested(true, &)
    end

    def untested(&)
      scoped_tested(false, &)
    end

    # Evaluate an if/while/until condition: run the command in a tested context
    # (so a failing condition never trips errexit) and report whether it succeeded.
    def succeeds?(command)
      tested { run(command) }.success?
    end

    # The errexit leaf check (POSIX 2.8.1): under `set -e`, a command failing
    # outside a tested context aborts the shell with that status.
    def exit_on_error(status)
      raise ExitSignal, status.exitstatus if abort_on?(status)

      status
    end

    private

    def scoped_tested(value)
      previous = @tested
      @tested = value
      yield
    ensure
      @tested = previous
    end

    def abort_on?(status)
      @state.options.on?(:errexit) && !@tested && !status.success?
    end

    def redirect_into(redirect, io)
      redirections.fetch(redirect.kind).apply(redirect, expander.expand_value(redirect.target), io, system)
    end
  end
end
