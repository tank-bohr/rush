# frozen_string_literal: true

module Rush
  # The shell's trap actions, keyed by canonical signal name (see Rush::Signals).
  # An action is the command string to run when the signal fires; "" means the
  # signal is ignored. Resetting a signal drops its entry, restoring the default.
  class TrapTable
    def initialize = @actions = {}

    def set(name, action) = @actions[name] = action

    def clear(name) = @actions.delete(name)

    def action(name) = @actions[name]

    # [name, action] pairs ordered by signal number, for `trap` with no operands.
    def listing = @actions.sort_by { |name, _action| Signals.number(name) }
  end
end
