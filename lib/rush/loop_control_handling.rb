# frozen_string_literal: true

module Rush
  # Shared break/continue handling for the loop runners. A multi-level signal is
  # re-raised with one fewer level so the next enclosing loop handles it; a
  # single-level signal stops here and yields the last command status. Hosts must
  # expose @executor.
  module LoopControlHandling
    private

    def unwind(signal)
      relayed = relay(signal)
      raise relayed if relayed

      @executor.state.last_status
    end

    def relay(signal)
      signal.class.new(signal.count - 1) if signal.count > 1
    end
  end
end
