# typed: true
# frozen_string_literal: true

module Rush
  # Resolves a %job_id operand (POSIX 2.12 Job Control Job ID) against the
  # job table: % / %% / %+ name the current job, %- the previous one, %n job
  # number n. dash keeps no command text away from a tty, so %string and
  # %?string prefixes match nothing here — No such job, exactly like the
  # oracle. A failed resolution raises JobError carrying dash's message; the
  # consuming builtin prefixes its name and fails with status 2.
  class JobSpec
    extend T::Sig

    NUMBER = /\A%\d+\z/

    # Fork-inherited display copies resolve for nobody: the jobs listing
    # shows them (POSIX 2.12 duplicate), but wait/kill/fg/bg in a forked
    # child answer No such job, exactly like dash (probed: a pipeline
    # stage lists [1] while `wait %1` in the same stage reports rc=2).
    sig { params(jobs: JobTable, spec: String).returns(JobTable::Job) }
    def self.resolve(jobs, spec)
      case spec
      when '%', '%%', '%+' then live(jobs.current) || missing('current')
      when '%-' then live(jobs.previous) || missing('previous')
      else by_number(jobs, spec)
      end
    end

    sig { params(jobs: JobTable, spec: String).returns(JobTable::Job) }
    def self.by_number(jobs, spec)
      unknown(spec) unless spec.match?(NUMBER)

      live(jobs.numbered(Integer(spec.delete_prefix('%'), 10))) || unknown(spec)
    end

    sig { params(job: T.nilable(JobTable::Job)).returns(T.nilable(JobTable::Job)) }
    def self.live(job)
      job if job && !job.inherited?
    end

    sig { params(which: String).returns(T.noreturn) }
    def self.missing(which)
      raise JobError, "No #{which} job"
    end

    sig { params(spec: String).returns(T.noreturn) }
    def self.unknown(spec)
      raise JobError, "No such job: #{spec}"
    end
  end
end
