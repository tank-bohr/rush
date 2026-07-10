# typed: true
# frozen_string_literal: true

module Rush
  # The monitor-mode (`set -m`) policy: whether job control is active here,
  # and the side effects of flipping the flag. Stateless — Executor builds one
  # on demand; the root-shell/forked-child bit lives in the JobTable. dash
  # 0.5.13 is the oracle throughout (probed off-tty, journal): enabling
  # monitor ignores SIGTSTP in the shell — as a base disposition, so a user
  # trap overrides it and `trap -` restores it — and puts every forked job
  # (background list, pipeline, subshell, external command) into its own
  # process group, first process as leader; command substitution stays in the
  # shell's group. The machinery is root-shell-only: a forked child keeps `m`
  # in $- but re-enabling there is flag-only, exactly like dash's rootshell
  # guard. An interactive shell additionally needs tty access to turn monitor
  # on; without one it warns and leaves the flag off.
  class JobControl
    extend T::Sig

    TSTP_IGNORE = T.let(proc {}, Proc)

    sig { params(executor: Executor).void }
    def initialize(executor)
      @executor = executor
    end

    # `set -m` (and -o monitor, and invocation-time -m via #startup). Can
    # refuse — no platform support, or an interactive shell without a tty —
    # in which case the flag stays off and the failure is only a warning, as
    # dash's setjobctl does.
    sig { params(stderr: T.untyped).void }
    def enable(stderr)
      return refuse(stderr, 'job control not supported') unless @executor.system.job_control_supported?
      return refuse(stderr, "can't access tty; job control turned off") if interactive? && !tty?

      options.set(:monitor, true)
      @executor.trap_runner.set_base('TSTP', TSTP_IGNORE) if @executor.jobs.root
    end

    # `set +m`: the flag drops and SIGTSTP returns to the OS default.
    sig { void }
    def disable
      options.set(:monitor, false)
      @executor.trap_runner.set_base('TSTP', nil) if @executor.jobs.root
    end

    # Invocation-time -m (rush -m, or -i -m): the flag was set while building
    # the shell state, before any executor existed to carry the side effects.
    # Re-run it through #enable so an interactive shell without a tty drops
    # the flag (dash: "can't access tty" at startup), and a permitted one gets
    # its SIGTSTP base disposition.
    sig { void }
    def startup
      return unless options.on?(:monitor)

      options.set(:monitor, false)
      enable(@executor.system.stderr)
    end

    # Process grouping is active: monitor is on and this is the root shell.
    # Forked children inherit `m` in $- but none of the machinery (dash's
    # rootshell guard, probed via nested groups and subshell `set -m`).
    sig { returns(T::Boolean) }
    def monitored?
      @executor.jobs.root && options.on?(:monitor)
    end

    # Fork one member of a job, into `leader`'s process group (its own when
    # none) under job control. Grouping is decided before the fork, so a
    # child entering its subshell environment cannot flip it.
    sig { params(leader: T.nilable(Integer), child_main: T.proc.returns(T.untyped)).returns(Integer) }
    def launch(leader: nil, &child_main)
      return @executor.system.fork(&child_main) || 0 unless monitored?

      @executor.system.fork_grouped(leader&.positive? ? leader : 0, &child_main) || 0
    end

    private

    sig { params(stderr: T.untyped, message: String).void }
    def refuse(stderr, message)
      stderr.puts("rush: #{message}")
    end

    # The rough dash test (it walks /dev/tty then fds 0..2): monitor in an
    # interactive shell needs a terminal to hand around. Refined to tcgetpgrp
    # in the terminal-handover slice (rush-mv8.3).
    sig { returns(T::Boolean) }
    def tty?
      @executor.system.tty? || @executor.system.stderr_tty?
    end

    sig { returns(T::Boolean) }
    def interactive?
      options.on?(:interactive)
    end

    sig { returns(Options) }
    def options
      @executor.state.options
    end
  end
end
