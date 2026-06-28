# frozen_string_literal: true

module Rush
  # Immutable result of running a command. $? can hold a value wider than a byte:
  # dash keeps `return 300` as 300 in-process, and only wraps to 0-255 at a real
  # process boundary (exit!/the shell's own exit, where the OS truncates). The
  # operand is validated non-negative and <= INT_MAX before reaching here.
  class Status
    attr_reader :exitstatus

    def initialize(exitstatus)
      @exitstatus = exitstatus
    end

    def success?
      exitstatus.zero?
    end

    def self.success
      new(0)
    end

    def self.failure(code = 1)
      new(code)
    end

    # A signalled process reports no exitstatus; POSIX maps it to 128 + signal.
    def self.of(process_status)
      new(process_status.exitstatus || (process_status.termsig + 128))
    end
  end
end
