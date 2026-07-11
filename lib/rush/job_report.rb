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
      head = "[#{job.number}] #{mark(table, job)} #{pid_field}#{job.display_state}"
      "#{head.ljust(33)}#{job.text}"
    end

    # + marks the current job, - the previous one (newest-first order).
    sig { params(table: JobTable, job: JobTable::Job).returns(String) }
    def self.mark(table, job)
      index = T.must(table.ordered.index(job))
      ['+', '-'].fetch(index, ' ')
    end
  end
end
