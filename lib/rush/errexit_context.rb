# typed: true
# frozen_string_literal: true

module Rush
  # Tracks whether a command is executing in a POSIX "tested" context where
  # errexit is suppressed, and performs the leaf `set -e` abort check.
  class ErrexitContext
    extend T::Sig

    sig { params(state: ShellState).void }
    def initialize(state)
      @state = state
      @tested = false
    end

    # Run the block with the tested flag swapped to `value` — true suppresses
    # errexit, false starts a fresh untested context — restoring the caller's
    # flag on exit.
    sig do
      type_parameters(:U)
        .params(value: T::Boolean, blk: T.proc.returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def scoped(value, &blk)
      previous = @tested
      @tested = value
      yield
    ensure
      @tested = previous
    end

    sig { params(status: Status).returns(Status) }
    def exit_on_error(status)
      raise ExitSignal, status.exitstatus if abort_on?(status)

      status
    end

    private

    sig { params(status: Status).returns(T::Boolean) }
    def abort_on?(status)
      !!(@state.options.on?(:errexit) && !@tested && !status.success?)
    end
  end
end
