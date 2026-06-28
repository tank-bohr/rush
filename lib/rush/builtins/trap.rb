# frozen_string_literal: true

module Rush
  module Builtins
    # `trap [action] signal...` sets, ignores ("" action) or resets ("-" action)
    # the handler for each signal; EXIT (or 0) runs when the shell exits. With no
    # operands it lists the active traps, one `trap -- 'action' NAME` line each in
    # signal-number order. The action word is consumed only when a signal follows
    # it, so `trap INT` resets INT (matching dash). A spec that names no signal is
    # reported as "trap: SPEC: bad trap" and stops processing with status 1.
    class Trap < Base
      def call
        return list if operands.empty?

        apply(*split)
      end

      private

      def split
        return [nil, operands] if operands.size < 2

        [operands.first, operands.drop(1)]
      end

      # Apply left to right, stopping at (but keeping the work before) the first
      # spec that names no signal — dash's behaviour for `trap x INT BADD TERM`.
      def apply(action, signals)
        bad = signals.find { |spec| !place(action, spec) }
        bad ? bad_trap(bad) : success
      end

      def place(action, spec)
        name = Signals.decode(spec)
        change(name, action) if name
        name
      end

      def change(name, action)
        reset?(action) ? executor.reset_trap(name) : executor.set_trap(name, action)
      end

      def reset?(action) = !action || action == '-'

      def bad_trap(spec)
        stderr.puts("trap: #{spec}: bad trap")
        failure(1)
      end

      def list
        traps.listing.each { |name, action| stdout.puts(line(name, action)) }
        success
      end

      def line(name, action) = "trap -- #{quote(action)} #{name}"

      def quote(action) = "'#{action.gsub("'", %q('"'"'))}'"

      def traps = executor.state.traps
    end
  end
end
