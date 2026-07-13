# typed: true
# frozen_string_literal: true

module Rush
  # Owns the executor's signal/trap handling: it records a trap, installs or
  # clears the matching OS disposition, runs a delivered signal's action (with $?
  # preserved, POSIX 2.14), and runs the EXIT trap as the shell terminates. Trap
  # bodies are parsed and run back through the executor, so this collaborates with
  # it rather than re-implementing execution.
  class TrapRunner
    extend T::Sig

    sig { params(executor: Executor).void }
    def initialize(executor)
      @executor = executor
      @exit_trap = ExitTrap.new(executor)
      @pending = PendingSignals.new
      @base = T.let(
        {}, #: Hash[String, Proc]
        T::Hash[String, Proc]
      )
    end

    # The session's base dispositions (the interactive INT/QUIT/TERM handlers):
    # what `trap - SIG` and an untouched signal fall back to instead of the OS
    # default. Subshells drop them (POSIX: caught signals reset in subshells).
    sig { params(handlers: T::Hash[String, Proc]).void }
    def install_base(handlers)
      @base = handlers
      handlers.each_key { |name| install_signal(name, :default) }
    end

    # Flip one base disposition without disturbing the rest — `set -m` adds and
    # removes SIGTSTP's this way mid-session (nil removes). A user trap on the
    # signal keeps the disposition it installed (dash-verified in both orders);
    # the base table still updates underneath, so a later `trap -` falls back
    # correctly.
    sig { params(name: String, handler: T.nilable(Proc)).void }
    def set_base(name, handler)
      @base.delete(name)
      @base[name] = handler if handler
      install_signal(name, :default) unless state.traps.action(name)
    end

    # Run the EXIT trap (if any) as the shell terminates, returning the status the
    # shell exits with: the given code, unless the trap itself runs `exit`. $?
    # inside the trap is that same code (POSIX 2.14), so it is published first.
    sig { params(code: Integer).returns(Integer) }
    def run_exit_trap(code)
      run_pending
      @exit_trap.run(code)
    end

    # Evaluate caught traps only at explicit shell checkpoints, never from the
    # Ruby Signal.trap callback. No delivery guard: dash permits nested and
    # same-signal traps to run at command boundaries inside an action.
    sig { void }
    def run_pending
      @pending.drain { |name| deliver(name) }
    end

    sig { params(status: Status).returns(Status) }
    def complete(status)
      state.record_status(status).tap { run_pending }
    end

    sig { returns(T::Boolean) }
    def pending?
      @pending.any?
    end

    sig { returns(T.nilable(Integer)) }
    def pending_exitstatus
      @pending.first&.then { |name| Signals.number(name) + 128 }
    end

    # The status a bare `exit` reports: while the EXIT trap runs, the status the
    # shell is terminating with (POSIX), not the trap body's last $?; otherwise
    # the last command's status.
    sig { returns(Integer) }
    def exiting_status
      @exit_trap.status
    end

    # Record a trap and (for real signals, not EXIT) install its disposition so a
    # delivered signal runs the action / is ignored / restores the default.
    sig { params(name: String, action: String).void }
    def set(name, action)
      state.traps.set(name, action)
      install_signal(name, action)
    end

    sig { params(name: String).void }
    def reset(name)
      state.traps.clear(name)
      install_signal(name, :default)
    end

    sig { void }
    def reset_caught_for_subshell
      @exit_trap = ExitTrap.new(@executor)
      @pending.clear
      drop_base
      state.traps.reset_caught.each { |name| install_signal(name, :default) }
    end

    private

    sig { returns(ShellState) }
    def state
      @executor.state
    end

    sig { params(action: String).void }
    def fire(action)
      @executor.run(Parser.new(Lexer.new(action, aliases: state.aliases)).parse)
    rescue Error => e
      raise unless ErrorPolicy.decision(:signal_trap, e) == :ignore
    end

    # An untrappable signal (KILL/STOP) raises; keep the table entry like dash.
    sig { params(name: String, action: T.any(String, Symbol)).void }
    def install_signal(name, action)
      return if name == Signals::EXIT

      install(name, disposition(action))
    rescue ArgumentError, SystemCallError
      nil
    end

    # :default falls back to the session's base handler when one is installed
    # (an interactive shell survives INT/QUIT/TERM); otherwise the OS default.
    sig { params(name: String, disposition: T.nilable(String)).void }
    def install(name, disposition)
      base = @base.fetch(name, nil)
      return @executor.system.trap_signal(name, nil) { base.call } if disposition == 'SYSTEM_DEFAULT' && base

      @executor.system.trap_signal(name, disposition) { @pending.record(name) }
    end

    # Subshells reset the base handlers to the true OS default before the
    # per-trap reset, so a forked child dies on ^C like any non-interactive
    # process.
    sig { void }
    def drop_base
      dropped = @base
      @base = {}
      dropped.each_key { |name| install_signal(name, :default) }
    end

    # '' ignores the signal; :default restores the true OS disposition
    # (SYSTEM_DEFAULT = SIG_DFL — Ruby's plain 'DEFAULT' instead simulates the
    # signal by raising, which dies as an uncaught-exception traceback where
    # dash dies silently by signal); a command string installs the handler
    # block (nil disposition), matching SystemCalls#trap_signal.
    sig { params(action: T.any(String, Symbol)).returns(T.nilable(String)) }
    def disposition(action)
      { '' => 'IGNORE', :default => 'SYSTEM_DEFAULT' }.fetch(action, nil)
    end

    # Run a delivered signal's action, restoring $? so the interrupted code is
    # unaffected (POSIX 2.14); an `exit` in the action propagates and terminates.
    sig { params(name: String).void }
    def deliver(name)
      action = state.traps.action(name)
      state.preserve_status { fire(action) } if action
    end
  end
end
