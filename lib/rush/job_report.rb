# typed: true
# frozen_string_literal: true

module Rush
  # One line of the jobs listing — and, verbatim, of a pre-prompt
  # notification: "[n] mark " (plus "pid " under jobs -l), the state, padding
  # so the command text starts at column 34, then the text itself (empty
  # outside job control, where dash keeps none either). dash's showjob
  # format, shared by the jobs builtin and the Repl's notifier.
  module JobReport
    extend T::Sig

    sig { params(table: JobTable, job: JobTable::Job, pid_field: String).returns(String) }
    def self.line(table, job, pid_field = '')
      head = "[#{job.number}] #{mark(table, job)} #{pid_field}#{state(job)}"
      "#{head.ljust(33)}#{job.text}"
    end

    # + marks the current job, - the previous one (newest-first order).
    sig { params(table: JobTable, job: JobTable::Job).returns(String) }
    def self.mark(table, job)
      index = T.must(table.ordered.index(job))
      ['+', '-'].fetch(index, ' ')
    end

    # The state column (dash's statusfmt vocabulary): Running, a strsignal
    # Stopped flavour, Done/Done(n), or the killing signal's description.
    sig { params(job: JobTable::Job).returns(String) }
    def self.state(job)
      return 'Running' if job.running?
      return Signals.stop_description(T.must(job.stopsig)) if job.stopped?

      settled(job.status)
    end

    sig { params(status: Status).returns(String) }
    def self.settled(status)
      signal = status.termsig
      return Signals.description(signal) if signal

      code = status.exitstatus
      code.zero? ? 'Done' : "Done(#{code})"
    end
  end
end
