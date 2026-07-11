# typed: true
# frozen_string_literal: true

module Rush
  # The shell's grip on its controlling terminal under job control
  # (rush-mv8.3): who to hand it to, how to take it back, and what to restore
  # when monitor turns off. Acquired by JobControl#enable, dash's setjobctl:
  # `home` is the shell's own process group once it has made itself a leader,
  # `initial` the foreground group found at acquisition — where the terminal
  # returns on `set +m`. Durable job-control state, so it lives on the
  # JobTable beside the root-shell bit; forked children drop it with the rest
  # of the table.
  class Terminal
    extend T::Sig

    # dash setjobctl(1): find the tty, wait until the shell is in the
    # foreground, remember the terminal's owner, then become a process-group
    # leader and take the terminal. Probed: the dance runs whenever the tty
    # is reachable — interactive or not — and only an interactive shell (the
    # caller's concern) treats its failure as an error.
    sig { params(system: SystemCalls).returns(T.nilable(Terminal)) }
    def self.acquire(system)
      tty = system.open_tty
      return unless tty

      initial = wait_foreground(system, tty)
      initial ? take(system, tty, initial) : abandon(tty)
    end

    # Wait for the foreground: a shell started in the background must not
    # steal the terminal, so it stops itself (SIGTTIN to its own group, the
    # OS default for a background tty read) until a job-control parent
    # brings it to the front — dash's killpg(0, SIGTTIN) loop. An unreadable
    # foreground group (tcgetpgrp answering nothing) falls out as nil.
    sig { params(system: SystemCalls, tty: T.untyped).returns(T.nilable(Integer)) }
    def self.wait_foreground(system, tty)
      while (pgrp = system.tcgetpgrp(tty))
        return pgrp if pgrp == system.pgrp

        system.kill('TTIN', 0)
      end
    end

    # Become a process-group leader and take the tty (dash: setpgid(0,
    # rootpid); xtcsetpgrp): `home` — where foreground jobs return the
    # terminal — is the shell's own group, its pid, from here on.
    sig { params(system: SystemCalls, tty: T.untyped, initial: Integer).returns(Terminal) }
    def self.take(system, tty, initial)
      system.setpgid(0, 0)
      new(system: system, tty: tty, home: system.pid, initial: initial).tap(&:reclaim)
    end

    # A tty whose foreground group cannot be read is no terminal at all
    # (dash: tcgetpgrp failing is the "can't access tty" case).
    sig { params(tty: T.untyped).returns(NilClass) }
    def self.abandon(tty)
      tty.close
      nil
    end

    # The parent-side handover around a foreground wait: give for the
    # block, reclaim after — bare when no terminal is held (or for a fake
    # fork's pid-0 launch).
    sig do
      type_parameters(:U)
        .params(terminal: T.nilable(Terminal), leader: Integer, blk: T.proc.returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def self.while_held(terminal, leader, &blk)
      return yield unless terminal && leader.positive?

      terminal.while_given(leader, &blk)
    end

    private_class_method :wait_foreground, :take, :abandon

    sig { returns(T.untyped) }
    attr_reader :tty

    sig { params(system: SystemCalls, tty: T.untyped, home: Integer, initial: Integer).void }
    def initialize(system:, tty:, home:, initial:)
      @system = system
      @tty = tty
      @home = home
      @initial = initial
    end

    # Hand the terminal to a foreground job's process group (dash forkchild).
    sig { params(pgid: Integer).void }
    def give(pgid)
      @system.tcsetpgrp(@tty, pgid)
    end

    # Take the terminal back once the foreground job settles (dash
    # waitforjob).
    sig { void }
    def reclaim
      give(@home)
    end

    # A foreground job's whole run: the job's group holds the terminal for
    # the duration of the block (the wait), and the shell takes it back
    # however the wait ends.
    sig do
      type_parameters(:U)
        .params(pgid: Integer, blk: T.proc.returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def while_given(pgid, &blk)
      give(pgid)
      yield
    ensure
      reclaim
    end

    # `set +m`: the terminal returns to whoever owned it at acquisition, the
    # shell rejoins that group, and the tty handle is released (dash
    # setjobctl(0)).
    sig { void }
    def restore
      give(@initial)
      @system.setpgid(0, @initial)
      @tty.close
    end
  end
end
