# typed: true
# frozen_string_literal: true

module Rush
  # Shared break/continue handling for the loop runners. A multi-level signal is
  # re-raised with one fewer level so the next enclosing loop handles it; a
  # single-level signal stops here and yields the last command status. Hosts must
  # expose @executor.
  module LoopControlHandling
    extend T::Sig

    private

    sig { params(signal: LoopControl).returns(Status) }
    def unwind(signal)
      relayed = relay(signal)
      # Kernel.raise (not bare raise): in this mixin Sorbet can't resolve a bare
      # raise on the module's self (the same reason ClosedStream uses Kernel.raise).
      Kernel.raise relayed if relayed

      @executor.state.last_status
    end

    sig { params(signal: LoopControl).returns(T.nilable(LoopControl)) }
    def relay(signal)
      signal.class.new(signal.count - 1) if signal.count > 1
    end
  end
end
