# typed: true
# frozen_string_literal: true

module Rush
  # dash's printsignal(): when a foreground wait reaps a child that died by a
  # signal other than SIGINT/SIGPIPE, the shell writes the strsignal
  # description — "Killed", "Terminated", " (core dumped)" suffixed when the
  # OS recorded a dump — to the stderr in effect at that wait. The wait
  # builtin reports the same for pid/%id operands; a bare `wait` never
  # reports (probed, rush-hkp). Methods are explicit singletons, like
  # Signals (module_function leaves unkillable instance-side copies).
  module SignalReport
    extend T::Sig

    # dash's exclusions: SIGINT ends interactive commands routinely and
    # SIGPIPE is the normal fate of a producer feeding a finished consumer.
    SILENT = T.let([Signals.number('INT'), Signals.number('PIPE')].freeze, T::Array[Integer])

    # Report onto err and hand the status back, so reap sites stay
    # expressions. A closed stderr swallows the report, not the status.
    sig { params(status: Status, err: T.untyped).returns(Status) }
    def self.report(status, err)
      err.puts(line(status)) if report?(status)
      status
    rescue Errno::EBADF
      status
    end

    sig { params(status: Status).returns(T::Boolean) }
    def self.report?(status)
      signal = status.termsig
      !!signal && !SILENT.include?(signal)
    end

    sig { params(status: Status).returns(String) }
    def self.line(status)
      description = Signals.description(T.must(status.termsig))
      status.coredump? ? "#{description} (core dumped)" : description
    end
  end
end
