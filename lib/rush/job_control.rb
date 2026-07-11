# typed: true
# frozen_string_literal: true

module Rush
  # The monitor-mode (`set -m`) policy: whether job control is active here,
  # and the side effects of flipping the flag. Stateless — Executor builds one
  # on demand; the durable bits (root shell, acquired terminal) live on the
  # JobTable's Control. dash 0.5.13 is the oracle throughout (probed on and
  # off a tty, journal): enabling monitor ignores SIGTSTP in the shell — as a
  # base disposition, so a user trap overrides it and `trap -` restores it —
  # and puts every forked job (background list, pipeline, subshell, external
  # command) into its own process group, first process as leader; command
  # substitution stays in the shell's group. Whenever the controlling
  # terminal is reachable — interactive or not — the shell additionally does
  # dash's setjobctl dance: wait until it is in the foreground, remember the
  # terminal's owner, make itself a process-group leader, take the terminal,
  # and ignore SIGTTOU too; foreground jobs then own the tty for the length
  # of their run. Only an interactive shell treats a missing tty as an error
  # (warn, flag off). The machinery is root-shell-only: a forked child keeps
  # `m` in $- but re-enabling there is flag-only, exactly like dash's
  # rootshell guard.
  class JobControl
    extend T::Sig

    IGNORE = T.let(proc {}, Proc)

    sig { params(executor: Executor).void }
    def initialize(executor)
      @executor = executor
    end

    # `set -m` (and -o monitor, and invocation-time -m via #startup). Can
    # refuse — no platform support, or an interactive shell without a tty —
    # in which case the flag stays off and the failure is only a warning, as
    # dash's setjobctl does. Re-enabling while on is a no-op (dash: on ==
    # jobctl), preserving the remembered terminal owner.
    sig { params(stderr: T.untyped).void }
    def enable(stderr)
      return refuse(stderr, 'job control not supported') unless @executor.system.job_control_supported?
      return if options.on?(:monitor)
      return options.set(:monitor, true) unless control.root

      enable_root(stderr)
    end

    # `set +m`: the flag drops, SIGTSTP and SIGTTOU return to the OS default
    # (dash setjobctl(0) runs both setsignals unconditionally), and the
    # terminal goes back to whoever owned it at acquisition.
    sig { void }
    def disable
      options.set(:monitor, false)
      drop_monitor if control.root
    end

    # Invocation-time -m (explicit, or defaulted on for an interactive
    # shell like dash's mflag = iflag): the flag was set while building the
    # shell state, before any executor existed to carry the side effects.
    # Re-run it through #enable so an interactive shell without a tty drops
    # the flag (dash: "can't access tty" at startup), and a permitted one
    # acquires the terminal and its base dispositions.
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
      control.monitor?
    end

    # Fork one member of a foreground job, into `leader`'s process group
    # (its own when none) under job control; a group leader also takes the
    # terminal, child-side, when the shell holds one. Grouping is decided
    # before the fork, so a child entering its subshell environment cannot
    # flip it.
    sig { params(leader: T.nilable(Integer), child_main: T.proc.returns(T.untyped)).returns(Integer) }
    def launch(leader: nil, &child_main)
      return @executor.system.fork(&child_main) || 0 unless monitored?

      group = leader&.positive? ? leader : 0
      @executor.system.fork_grouped(group, handover_tty(group), &child_main) || 0
    end

    # An asynchronous (&) job: its own group under job control, but never
    # the terminal — probed: the tty stays with the shell.
    sig { params(child_main: T.proc.returns(T.untyped)).returns(Integer) }
    def launch_background(&child_main)
      return @executor.system.fork(&child_main) || 0 unless monitored?

      @executor.system.fork_grouped(0, &child_main) || 0
    end

    # Wait for a foreground job with the terminal handed to its process
    # group, taking it back once the job settles, however the wait ends
    # (dash's waitforjob). The give here is the parent-side settle — it also
    # covers the spawn path, which has no child-side hook — and without a
    # held terminal the wait runs bare. A wait that answers "stopped" (^Z
    # under the WUNTRACED waits) parks the whole job in the table on the
    # way out, where jobs/wait/kill find it.
    sig { params(pids: T::Array[Integer], text: T.nilable(String), blk: T.proc.returns(Status)).returns(Status) }
    def foreground(pids, text: nil, &blk)
      status = Terminal.while_held(control.terminal, pids.fetch(0), &blk)
      @executor.jobs.adopt_stopped(pids, T.must(status.stopsig), text) if status.stopped?
      status
    end

    # The command text a job-table entry keeps: rendered only under job
    # control — dash stores cmdtext for jobctl jobs alone, and that absence
    # is fg/bg's refusal bit.
    sig { params(node: AST::Node).returns(T.nilable(String)) }
    def job_text(node)
      CommandText.render(node) if control.monitor?
    end

    private

    # The root-shell side of `set -m`: with a reachable tty, the full dash
    # setjobctl dance; without one, grouping only — an error only for an
    # interactive shell.
    sig { params(stderr: T.untyped).void }
    def enable_root(stderr)
      terminal = Terminal.acquire(@executor.system)
      terminal ? enable_with_terminal(terminal) : enable_off_tty(stderr)
    end

    # SIGTSTP and SIGTTOU ignored (probed under a pty; SIGTTIN keeps the OS
    # default — that is what parks a background-started shell until fg), as
    # base dispositions: user traps win in either order and `trap -` falls
    # back here.
    sig { params(terminal: Terminal).void }
    def enable_with_terminal(terminal)
      control.engage(terminal)
      @executor.trap_runner.set_base('TSTP', IGNORE)
      @executor.trap_runner.set_base('TTOU', IGNORE)
      options.set(:monitor, true)
    end

    # Off-tty monitor is grouping, WUNTRACED waits and the SIGTSTP ignore
    # alone (probed: dash leaves TTOU stopping the shell there).
    sig { params(stderr: T.untyped).void }
    def enable_off_tty(stderr)
      return refuse(stderr, "can't access tty; job control turned off") if interactive?

      control.engage(nil)
      @executor.trap_runner.set_base('TSTP', IGNORE)
      options.set(:monitor, true)
    end

    # The root-shell side of `set +m`: both stop-signal bases return to the
    # OS default and the terminal, when held, goes home.
    sig { void }
    def drop_monitor
      @executor.trap_runner.set_base('TSTP', nil)
      @executor.trap_runner.set_base('TTOU', nil)
      control.terminal&.restore
      control.release
    end

    # The tty a freshly forked job leader should take with it (dash
    # forkchild's FORK_FG xtcsetpgrp): only a group leader, only while the
    # shell holds the terminal. Joiners find the group already in front.
    sig { params(group: Integer).returns(T.untyped) }
    def handover_tty(group)
      return if group.nonzero?

      control.terminal&.tty
    end

    sig { params(stderr: T.untyped, message: String).void }
    def refuse(stderr, message)
      stderr.puts("rush: #{message}")
    end

    sig { returns(JobTable::Control) }
    def control
      @executor.jobs.control
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
