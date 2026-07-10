# typed: true
# frozen_string_literal: true

module Rush
  # Immutable result of running a command. $? can hold a value wider than a byte:
  # dash keeps `return 300` as 300 in-process, and only wraps to 0-255 at a real
  # process boundary (exit!/the shell's own exit, where the OS truncates). The
  # operand is validated non-negative and <= INT_MAX before reaching here.
  # Under job control a WUNTRACED wait can answer for a job that STOPPED rather
  # than ended: stopsig carries the stopping signal, and the exitstatus is
  # dash's view of the pair — normally 128+stopsig, but a mixed pipeline keeps
  # the last stage's exit code while the job as a whole is stopped (probed).
  class Status
    extend T::Sig

    sig { returns(Integer) }
    attr_reader :exitstatus

    sig { returns(T.nilable(Integer)) }
    attr_reader :stopsig

    sig { returns(T.nilable(Integer)) }
    attr_reader :termsig

    sig { params(exitstatus: Integer, stopsig: T.nilable(Integer), termsig: T.nilable(Integer)).void }
    def initialize(exitstatus, stopsig: nil, termsig: nil)
      @exitstatus = exitstatus
      @stopsig = stopsig
      @termsig = termsig
    end

    sig { returns(T::Boolean) }
    def success?
      exitstatus.zero?
    end

    # The job this status describes is stopped, not gone: the foreground
    # wait hands it back to the prompt as a Stopped job-table entry.
    sig { returns(T::Boolean) }
    def stopped?
      !!@stopsig
    end

    # The same verdict, carrying a sibling stage's stop signal: dash keeps
    # the last stage's exit code even when an earlier stage's ^Z parked the
    # whole pipeline (probed: stopped|exit5 answers 5, with the job
    # Stopped), so the job's stoppedness rides along on the chosen status.
    sig { params(stopsig: T.nilable(Integer)).returns(Status) }
    def with_stop(stopsig)
      stopped? || !stopsig ? self : Status.new(exitstatus, stopsig: stopsig)
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
    # to a plain Integer without changing behaviour on any reachable path. A
    # stopped child (WUNTRACED) maps to 128 + stopsig with the signal kept.
    sig { params(process_status: Process::Status).returns(Status) }
    def self.of(process_status)
      return stopped(process_status.stopsig.to_i) if process_status.stopped?

      signal = process_status.termsig
      new(process_status.exitstatus || (signal.to_i + 128), termsig: signal)
    end

    sig { params(stopsig: Integer).returns(Status) }
    def self.stopped(stopsig)
      new(stopsig + 128, stopsig: stopsig)
    end
  end
end
