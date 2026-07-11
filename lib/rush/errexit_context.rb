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

    # Run the block in a "tested" context (errexit suppressed): the condition of
    # if/while/until, the non-final part of an && / || list, a negated pipeline,
    # and an async (&) command. Restores on exit, so the flag follows the call tree.
    sig do
      type_parameters(:U)
        .params(blk: T.proc.returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def tested(&blk)
      scoped(true, &blk)
    end

    # The inverse: a fresh untested context regardless of the caller's, the way
    # command substitution starts one.
    sig do
      type_parameters(:U)
        .params(blk: T.proc.returns(T.type_parameter(:U)))
        .returns(T.type_parameter(:U))
    end
    def untested(&blk)
      scoped(false, &blk)
    end

    # The errexit leaf check (POSIX 2.8.1): under `set -e`, a command failing
    # outside a tested context aborts the shell with that status.
    sig { params(status: Status).returns(Status) }
    def exit_on_error(status)
      raise ExitSignal, status.exitstatus if abort_on?(status)

      status
    end

    private

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

    sig { params(status: Status).returns(T::Boolean) }
    def abort_on?(status)
      !!(@state.options.on?(:errexit) && !@tested && !status.success?)
    end
  end
end
