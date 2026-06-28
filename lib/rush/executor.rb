# frozen_string_literal: true

module Rush
  # Walks the AST by polymorphic dispatch (node.execute(self)) over shared shell
  # state, with all OS access funneled through the injected SystemCalls port. The
  # base IoTable, builtin registry, redirection registry and expander hang off it.
  class Executor
    attr_reader :system, :state, :builtins, :redirections, :expander, :io, :cmd_sub_status

    def initialize(system:, state:, builtins: Builtins.default_registry)
      @system = system
      @state = state
      @builtins = builtins
      setup
    end

    # A redirect that fails at runtime (n>&m to a fd that is not open) leaves the
    # command unrun with status 2; the shell carries on (RedirectError).
    def run(node)
      @state.last_status = node.execute(self)
    rescue RedirectError
      @state.last_status = Status.new(2)
    end

    # Permanently rebind the base IoTable (the `exec` redirection-only form),
    # unlike with_io which restores afterwards.
    def replace_io(table) = @io = table

    def run_simple(command) = CommandRunner.new(self, command).call

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
    def run_redirected(command, redirects) = with_redirects(redirects) { |io| with_io(io) { run(command) } }

    # The exit status of the last command substitution performed while a simple
    # command is being built. Reset to success at the start of each command so a
    # no-command-word command (only assignments/redirections) reports 0 unless a
    # substitution sets it (POSIX 2.9.1: such a command takes the status of the
    # last command substitution). Kept off last_status so a later $? in the same
    # command still sees the previous command's status, as dash does.
    def reset_cmd_sub_status = @cmd_sub_status = Status.success

    def record_cmd_sub_status(status) = @cmd_sub_status = status

    # Run the EXIT trap (if any) as the shell terminates, returning the status
    # the shell exits with: the given code, unless the trap itself runs `exit`.
    # $? inside the trap is that same code (POSIX 2.14), so it is published first.
    def run_exit_trap(code)
      action = state.traps.action(Signals::EXIT)
      return code unless action

      state.last_status = Status.new(code)
      fire_exit(action, code)
    end

    # The status a bare `exit` reports: while the EXIT trap runs, the status the
    # shell is terminating with (POSIX), not the trap body's last $?; otherwise
    # the last command's status.
    def exiting_status = @exiting || state.last_status.exitstatus

    # Record a trap and (for real signals, not EXIT) install its disposition so a
    # delivered signal runs the action / is ignored / restores the default.
    def set_trap(name, action)
      state.traps.set(name, action)
      install_signal(name, action) unless name == Signals::EXIT
    end

    def reset_trap(name)
      state.traps.clear(name)
      install_signal(name, :default) unless name == Signals::EXIT
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
    def tested(&) = scoped_tested(true, &)

    def untested(&) = scoped_tested(false, &)

    # Evaluate an if/while/until condition: run the command in a tested context
    # (so a failing condition never trips errexit) and report whether it succeeded.
    def succeeds?(command) = tested { run(command) }.success?

    # The errexit leaf check (POSIX 2.8.1): under `set -e`, a command failing
    # outside a tested context aborts the shell with that status.
    def exit_on_error(status)
      raise ExitSignal, status.exitstatus if abort_on?(status)

      status
    end

    private

    def setup
      @redirections = Redirection.default_registry
      @expander = Expansion::Pipeline.new(self)
      @io = IoTable.standard(@system)
      @tested = false
      @state.seed_pwd(@system.pwd)
    end

    def scoped_tested(value)
      previous = @tested
      @tested = value
      yield
    ensure
      @tested = previous
    end

    def abort_on?(status) = @state.option?(:errexit) && !@tested && !status.success?

    def redirect_into(redirect, io)
      redirections.fetch(redirect.kind).apply(redirect, expander.expand_value(redirect.target), io, system)
    end

    def fire_exit(action, code)
      with_exiting(code) { fire(action) }
      code
    rescue ExitSignal => e
      e.code
    end

    # Publish `code` as the status a bare `exit` in the action reports, cleared
    # afterwards so a bare exit elsewhere falls back to the last command status.
    def with_exiting(code)
      @exiting = code
      yield
    ensure
      @exiting = nil
    end

    def fire(action)
      run(Parser.new(Lexer.new(action, aliases: state.aliases)).parse)
    rescue ParseError, ExpansionError, ReadonlyError, LoopControl, ReturnSignal
      nil
    end

    # An untrappable signal (KILL/STOP) raises; keep the table entry like dash.
    def install_signal(name, action)
      system.trap_signal(name, disposition(action)) { fire_signal(name) }
    rescue ArgumentError, SystemCallError
      nil
    end

    # '' ignores the signal, :default restores it; a command string installs the
    # handler block (nil disposition), matching SystemCalls#trap_signal.
    def disposition(action) = { '' => 'IGNORE', :default => 'DEFAULT' }[action]

    # Run a delivered signal's action, restoring $? so the interrupted code is
    # unaffected (POSIX 2.14); an `exit` in the action propagates and terminates.
    def fire_signal(name)
      saved = state.last_status
      fire(state.traps.action(name).to_s)
      state.last_status = saved
    end
  end
end
