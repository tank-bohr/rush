# typed: true
# frozen_string_literal: true

module Rush
  class JobTable
    # The job-control environment of this shell: the root-shell bit, how
    # this shell treats stopped children (bare waits, engaged monitor
    # machinery, or a stage's stop relay), and — with a tty — the acquired
    # controlling terminal. dash's rootshell/jobctl guards and
    # ttyfd/initialpgrp globals; monitor and terminal drop together when a
    # forked child clears its job table, while an armed relay survives the
    # fork so stops keep bubbling (rush-l4o).
    class Control
      extend T::Sig

      sig { returns(T::Boolean) }
      attr_reader :root

      sig { returns(T.nilable(Terminal)) }
      attr_reader :terminal

      sig { void }
      def initialize
        @root = T.let(true, T::Boolean)
        @stops = T.let(:default, Symbol)
        @terminal = T.let(nil, T.nilable(Terminal))
        @warning = T.let(0, Integer)
      end

      # Monitor machinery engaged in this shell (grouping, WUNTRACED waits,
      # stops adopted into the job table).
      sig { returns(T::Boolean) }
      def monitor?
        @stops == :monitor
      end

      # A pipeline stage forked from a monitor-mode shell is a transparent
      # member of its job: once armed, a stop this process's own foreground
      # wait reaps is re-raised onto the process itself, propagating the
      # stop to the job's owner (rush-l4o; dash reaches the same picture by
      # exec-ing simple stages in place). Armed child-side before the
      # subshell reset, while the parent's monitor bit is still readable.
      sig { void }
      def arm_stage_relay
        @stops = :relay if monitor?
      end

      sig { returns(T::Boolean) }
      def relay?
        @stops == :relay
      end

      # Stops are visible to this shell's waits: the monitor adopts them,
      # the relay re-raises them.
      sig { returns(T::Boolean) }
      def stoppable_waits?
        monitor? || relay?
      end

      # `set -m` accepted in the root shell: machinery on, holding the
      # terminal when one was acquired (nil off-tty — grouping still runs).
      sig { params(terminal: T.nilable(Terminal)).void }
      def engage(terminal)
        @stops = :monitor
        @terminal = terminal
      end

      sig { void }
      def release
        @stops = :default
        @terminal = nil
      end

      # A fork drops root, terminal and monitor together — but keeps an
      # armed relay, so stops bubble out of nested forks within a stage.
      sig { void }
      def fork_child
        @root = false
        @terminal = nil
        @stops = :default if monitor?
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
