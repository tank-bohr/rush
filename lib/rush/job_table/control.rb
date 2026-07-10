# typed: true
# frozen_string_literal: true

module Rush
  class JobTable
    # The job-control environment of this shell: the root-shell bit, whether
    # the monitor machinery is engaged (grouping, WUNTRACED waits), and — with
    # a tty — the acquired controlling terminal. dash's rootshell/jobctl
    # guards and ttyfd/initialpgrp globals; everything drops together when a
    # forked child clears its job table.
    class Control
      extend T::Sig

      sig { returns(T::Boolean) }
      attr_reader :root

      sig { returns(T::Boolean) }
      attr_reader :monitor

      sig { returns(T.nilable(Terminal)) }
      attr_reader :terminal

      sig { void }
      def initialize
        @root = T.let(true, T::Boolean)
        @monitor = T.let(false, T::Boolean)
        @terminal = T.let(nil, T.nilable(Terminal))
        @warning = T.let(0, Integer)
      end

      # `set -m` accepted in the root shell: machinery on, holding the
      # terminal when one was acquired (nil off-tty — grouping still runs).
      sig { params(terminal: T.nilable(Terminal)).void }
      def engage(terminal)
        @monitor = true
        @terminal = terminal
      end

      sig { void }
      def release
        @monitor = false
        @terminal = nil
      end

      sig { void }
      def fork_child
        @root = false
        release
      end

      # What a job created right now is born as: dash stamps each jobtab
      # entry with the jobctl in force at makejob time (probed across
      # -m/+m flips); only :monitored jobs may be fg/bg-resumed.
      sig { returns(Symbol) }
      def origin
        @monitor ? :monitored : :plain
      end

      # dash's job_warning: the first exit with a stopped job warns and is
      # refused; the window it opens lets the very next command's exit
      # through, and two interactive ticks re-arm it (a batch shell never
      # ticks, so it warns exactly once).
      sig { returns(T::Boolean) }
      def warn_exit?
        return false if @warning.positive?

        @warning = 2
        true
      end

      # One interactive turn passing (the Repl, as dash's cmdloop decrements
      # job_warning per iteration).
      sig { void }
      def tick_warning
        @warning -= 1 if @warning.positive?
      end
    end
  end
end
