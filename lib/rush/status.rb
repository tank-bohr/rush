# typed: true
# frozen_string_literal: true

module Rush
  # Immutable result of running a command. $? can hold a value wider than a byte:
  # dash keeps `return 300` as 300 in-process, and only wraps to 0-255 at a real
  # process boundary (exit!/the shell's own exit, where the OS truncates). The
  # operand is validated non-negative and <= INT_MAX before reaching here.
  class Status
    extend T::Sig

    sig { returns(Integer) }
    attr_reader :exitstatus

    sig { params(exitstatus: Integer).void }
    def initialize(exitstatus)
      @exitstatus = exitstatus
    end

    sig { returns(T::Boolean) }
    def success?
      exitstatus.zero?
    end

    sig { returns(Status) }
    def self.success
      new(0)
    end

    sig { params(code: Integer).returns(Status) }
    def self.failure(code = 1)
      new(code)
    end

    # A signalled process reports no exitstatus; POSIX maps it to 128 + signal.
    # termsig is Integer? to the type-checker (nil unless signalled); the signalled
    # branch here is the only one reached when exitstatus is nil, so .to_i pins it
    # to a plain Integer without changing behaviour on any reachable path.
    sig { params(process_status: Process::Status).returns(Status) }
    def self.of(process_status)
      new(process_status.exitstatus || (process_status.termsig.to_i + 128))
    end
  end
end
