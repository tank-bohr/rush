# typed: true
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
      extend T::Sig

      sig { returns(Status) }
      def call
        return list if operands.empty?

        action, signals = split
        apply(action, signals)
      end

      private

      # tuple, not Array: split feeds `apply(*split)`, a fixed-arity call.
      sig { returns([T.nilable(String), T::Array[String]]) }
      def split
        return [nil, operands] if operands.size < 2

        [operands.first, operands.drop(1)]
      end

      # Apply left to right, stopping at (but keeping the work before) the first
      # spec that names no signal — dash's behaviour for `trap x INT BADD TERM`.
      sig { params(action: T.nilable(String), signals: T::Array[String]).returns(Status) }
      def apply(action, signals)
        bad = signals.find { |spec| !place(action, spec) }
        bad ? bad_trap(bad) : success
      end

      sig { params(action: T.nilable(String), spec: String).returns(T.nilable(String)) }
      def place(action, spec)
        name = Signals.decode(spec)
        change(name, action) if name
        name
      end

      sig { params(name: String, action: T.nilable(String)).void }
      def change(name, action)
        if action && action != '-'
          executor.trap_runner.set(name, action)
        else
          executor.trap_runner.reset(name)
        end
      end

      sig { params(spec: String).returns(Status) }
      def bad_trap(spec)
        stderr.puts("trap: #{spec}: bad trap")
        failure(1)
      end

      sig { returns(Status) }
      def list
        traps.listing.each { |name, action| stdout.puts(line(name, action)) }
        success
      end

      sig { params(name: String, action: String).returns(String) }
      def line(name, action)
        "trap -- #{quote(action)} #{name}"
      end

      sig { params(action: String).returns(String) }
      def quote(action)
        "'#{action.gsub("'", %q('"'"'))}'"
      end

      sig { returns(TrapTable) }
      def traps
        executor.state.traps
      end
    end
  end
end
