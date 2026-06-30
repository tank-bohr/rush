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

      sig { returns(T.untyped) }
      def call
        return list if operands.empty?

        apply(*split)
      end

      private

      # tuple, not Array: split feeds `apply(*split)`, a fixed-arity call.
      sig { returns(T.untyped) }
      def split
        return [nil, operands] if operands.size < 2

        [operands.first, operands.drop(1)]
      end

      # Apply left to right, stopping at (but keeping the work before) the first
      # spec that names no signal — dash's behaviour for `trap x INT BADD TERM`.
      sig { params(action: T.untyped, signals: T.untyped).returns(T.untyped) }
      def apply(action, signals)
        bad = signals.find { |spec| !place(action, spec) }
        bad ? bad_trap(bad) : success
      end

      sig { params(action: T.untyped, spec: T.untyped).returns(T.untyped) }
      def place(action, spec)
        name = Signals.decode(spec)
        change(name, action) if name
        name
      end

      sig { params(name: T.untyped, action: T.untyped).returns(T.untyped) }
      def change(name, action)
        reset?(action) ? executor.trap_runner.reset(name) : executor.trap_runner.set(name, action)
      end

      sig { params(action: T.untyped).returns(T.untyped) }
      def reset?(action)
        !action || action == '-'
      end

      sig { params(spec: T.untyped).returns(T.untyped) }
      def bad_trap(spec)
        stderr.puts("trap: #{spec}: bad trap")
        failure(1)
      end

      sig { returns(T.untyped) }
      def list
        traps.listing.each { |name, action| stdout.puts(line(name, action)) }
        success
      end

      sig { params(name: T.untyped, action: T.untyped).returns(String) }
      def line(name, action)
        "trap -- #{quote(action)} #{name}"
      end

      sig { params(action: T.untyped).returns(String) }
      def quote(action)
        "'#{action.gsub("'", %q('"'"'))}'"
      end

      sig { returns(T.untyped) }
      def traps
        executor.state.traps
      end
    end
  end
end
