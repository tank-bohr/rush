# typed: true
# frozen_string_literal: true

module Rush
  # The shell's trap actions, keyed by canonical signal name (see Rush::Signals).
  # An action is the command string to run when the signal fires; "" means the
  # signal is ignored. Resetting a signal drops its entry, restoring the default.
  class TrapTable
    extend T::Sig

    sig { void }
    def initialize
      @actions = {}
    end

    sig { params(name: String, action: String).returns(String) }
    def set(name, action)
      @actions[name] = action
    end

    sig { params(name: String).returns(T.nilable(String)) }
    def clear(name)
      @actions.delete(name)
    end

    sig { params(name: String).returns(T.nilable(String)) }
    def action(name)
      @actions[name]
    end

    # [name, action] pairs ordered by signal number, for `trap` with no operands.
    sig { returns(T::Array[[String, String]]) }
    def listing
      @actions.sort_by { |name, _action| Signals.number(name) }
    end
  end
end
