# frozen_string_literal: true

module Rush
  # Immutable result of running a command: a POSIX exit status (0-255).
  class Status
    attr_reader :exitstatus

    # POSIX exit codes wrap modulo 256 (so `exit 300` yields 44, `exit -1` 255).
    def initialize(exitstatus) = @exitstatus = exitstatus % 256

    def success? = exitstatus.zero?

    def self.success = new(0)

    def self.failure(code = 1) = new(code)

    # A signalled process reports no exitstatus; POSIX maps it to 128 + signal.
    def self.of(process_status)
      new(process_status.exitstatus || (128 + process_status.termsig))
    end
  end
end
