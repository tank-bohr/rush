# typed: true
# frozen_string_literal: true

module Rush
  class JobTable
    # The job-control environment of this shell: the root-shell bit and,
    # while the root shell holds one, the acquired controlling terminal —
    # dash's rootshell guard and ttyfd/initialpgrp globals. Both drop
    # together when a forked child clears its job table.
    class Control
      extend T::Sig

      sig { returns(T::Boolean) }
      attr_reader :root

      sig { returns(T.nilable(Terminal)) }
      attr_reader :terminal

      sig { void }
      def initialize
        @root = T.let(true, T::Boolean)
        @terminal = T.let(nil, T.nilable(Terminal))
      end

      sig { params(terminal: T.nilable(Terminal)).void }
      def hold(terminal)
        @terminal = terminal
      end

      sig { void }
      def fork_child
        @root = false
        @terminal = nil
      end
    end
  end
end
