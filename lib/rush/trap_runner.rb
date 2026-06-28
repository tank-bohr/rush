# frozen_string_literal: true

module Rush
  # Owns the executor's signal/trap handling: it records a trap, installs or
  # clears the matching OS disposition, runs a delivered signal's action (with $?
  # preserved, POSIX 2.14), and runs the EXIT trap as the shell terminates. Trap
  # bodies are parsed and run back through the executor, so this collaborates with
  # it rather than re-implementing execution.
  class TrapRunner
    def initialize(executor)
      @executor = executor
      @state = executor.state
      @exiting = nil
    end

    # Run the EXIT trap (if any) as the shell terminates, returning the status the
    # shell exits with: the given code, unless the trap itself runs `exit`. $?
    # inside the trap is that same code (POSIX 2.14), so it is published first.
    def run_exit_trap(code)
      action = @state.traps.action(Signals::EXIT)
      return code unless action

      @state.record_status(Status.new(code))
      fire_exit(action, code)
    end

    # The status a bare `exit` reports: while the EXIT trap runs, the status the
    # shell is terminating with (POSIX), not the trap body's last $?; otherwise
    # the last command's status.
    def exiting_status
      @exiting || @state.last_status.exitstatus
    end

    # Record a trap and (for real signals, not EXIT) install its disposition so a
    # delivered signal runs the action / is ignored / restores the default.
    def set(name, action)
      @state.traps.set(name, action)
      install_signal(name, action) unless name == Signals::EXIT
    end

    def reset(name)
      @state.traps.clear(name)
      install_signal(name, :default) unless name == Signals::EXIT
    end

    private

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
      @executor.run(Parser.new(Lexer.new(action, aliases: @state.aliases)).parse)
    rescue ParseError, ExpansionError, ReadonlyError, LoopControl, ReturnSignal
      nil
    end

    # An untrappable signal (KILL/STOP) raises; keep the table entry like dash.
    def install_signal(name, action)
      @executor.system.trap_signal(name, disposition(action)) { fire_signal(name) }
    rescue ArgumentError, SystemCallError
      nil
    end

    # '' ignores the signal, :default restores it; a command string installs the
    # handler block (nil disposition), matching SystemCalls#trap_signal.
    def disposition(action)
      { '' => 'IGNORE', :default => 'DEFAULT' }[action]
    end

    # Run a delivered signal's action, restoring $? so the interrupted code is
    # unaffected (POSIX 2.14); an `exit` in the action propagates and terminates.
    def fire_signal(name)
      saved = @state.last_status
      fire(@state.traps.action(name).to_s)
      @state.record_status(saved)
    end
  end
end
