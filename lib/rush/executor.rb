# frozen_string_literal: true

module Rush
  # Walks the AST by polymorphic dispatch (node.execute(self)) over shared shell
  # state, with all OS access funneled through the injected SystemCalls port. The
  # base IoTable, builtin registry, redirection registry and expander hang off it.
  class Executor
    attr_reader :system, :state, :builtins, :redirections, :expander, :io

    def initialize(system:, state:, builtins: Builtins.default_registry)
      @system = system
      @state = state
      @builtins = builtins
      setup
    end

    def run(node) = @state.last_status = node.execute(self)

    # Permanently rebind the base IoTable (the `exec` redirection-only form),
    # unlike with_io which restores afterwards.
    def replace_io(table) = @io = table

    def run_simple(command) = CommandRunner.new(self, command).call

    # Build an IoTable by applying redirects on top of a base (the current base
    # IoTable by default); shared by simple commands and redirected compounds.
    def apply_redirects(redirects, base = @io)
      redirects.reduce(base) { |io, redirect| redirect_into(redirect, io) }
    end

    # Run a compound command with its redirects bound for the whole body.
    def run_redirected(command, redirects) = with_io(apply_redirects(redirects)) { run(command) }

    # Run the EXIT trap (if any) as the shell terminates, returning the status
    # the shell exits with: the given code, unless the trap itself runs `exit`.
    # $? inside the trap is that same code (POSIX 2.14), so it is published first.
    def run_exit_trap(code)
      action = state.traps.action(Signals::EXIT)
      return code unless action

      state.last_status = Status.new(code)
      fire_exit(action, code)
    end

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
      @state.pwd ||= @system.pwd
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
      fire(action)
      code
    rescue ExitSignal => e
      e.code
    end

    def fire(action)
      run(Parser.new(Lexer.new(action)).parse)
    rescue ParseError, ExpansionError, ReadonlyError, LoopControl, ReturnSignal
      nil
    end

    # An untrappable signal (KILL/STOP) raises; keep the table entry like dash.
    def install_signal(name, action)
      system.trap_signal(name, disposition(action)) { fire_signal(name) }
    rescue ArgumentError, SystemCallError
      nil
    end

    def disposition(action)
      return 'IGNORE' if action == ''
      return 'DEFAULT' if action == :default

      nil
    end

    # Run a delivered signal's action, restoring $? so the interrupted code is
    # unaffected (POSIX 2.14); an `exit` in the action propagates and terminates.
    def fire_signal(name)
      saved = state.last_status
      fire(state.traps.action(name).to_s)
      state.last_status = saved
    end
  end
end
