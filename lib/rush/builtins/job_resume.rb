# typed: true
# frozen_string_literal: true

module Rush
  module Builtins
    # Shared base of fg and bg: resolve each %id operand (no operand means
    # the current job, and an empty table is "No current job", like dash),
    # refuse a job that was not created under job control — dash's per-job
    # jobctl bit, independent of the monitor flag now in force (probed
    # across set -m/+m flips) — and resume survivors with SIGCONT to the
    # job's process group. dash loops multiple operands for both commands;
    # the last one's status is the builtin's.
    class JobResume < Base
      extend T::Sig

      sig { returns(Status) }
      def call
        specs = operands.empty? ? [nil] : operands
        specs.map { |spec| resume_one(spec) }.fetch(-1)
      rescue JobError => e
        bad(e.message)
      end

      private

      # A job outside job control aborts the whole command (dash's sh_error:
      # later operands never run), through the same status-2 error path as a
      # bad %id.
      sig { params(spec: T.nilable(String)).returns(Status) }
      def resume_one(spec)
        job = JobSpec.resolve(executor.jobs, spec || '%+')
        raise JobError, refusal(spec) unless job.controlled?

        resume(job)
      end

      # The subclass's whole move: bg lists and leaves the job running in
      # the background; fg reattaches and waits.
      sig { params(_job: JobTable::Job).returns(Status) }
      def resume(_job)
        # :nocov: overridden by fg/bg
        raise NotImplementedError
        # :nocov:
      end

      sig { params(spec: T.nilable(String)).returns(String) }
      def refusal(spec)
        spec ? "job #{spec} not created under job control" : 'job not created under job control'
      end

      sig { params(message: String).returns(Status) }
      def bad(message)
        stderr.puts("#{argv.fetch(0)}: #{message}")
        failure(2)
      end
    end

    # `fg [%id...]`: bring a job to the foreground — the command line goes
    # to stdout (an empty placeholder until the command-text column lands
    # with rush-mv8.6), SIGCONT resumes the group, the terminal follows it
    # (JobControl#foreground), and the shell waits as for any foreground
    # job: the job's status becomes $?, a ^Z parks it Stopped again under
    # the same number, and a finished job leaves the table (dash frees the
    # entry it fg-waited).
    class Fg < JobResume
      extend T::Sig

      private

      sig { params(job: JobTable::Job).returns(Status) }
      def resume(job)
        stdout.puts('')
        executor.job_control.foreground(job.members) do
          job.continue(executor.system)
          settle(job)
        end
      end

      # A finished job answers from memory (dash's fg on a dead-but-
      # remembered entry: getstatus, probed 137); a live one waits every
      # member (JobTable#settle_members).
      sig { params(job: JobTable::Job).returns(Status) }
      def settle(job)
        verdict = job.finished? ? job.status : executor.jobs.settle_members(job)
        executor.jobs.forget(job) unless verdict.stopped?
        verdict
      end
    end

    # `bg [%id...]`: resume a stopped job in the background — "[n] " and the
    # (mv8.6) command line to stdout, SIGCONT, the entry runs on in the
    # table and the terminal stays with the shell.
    class Bg < JobResume
      extend T::Sig

      private

      sig { params(job: JobTable::Job).returns(Status) }
      def resume(job)
        job.continue(executor.system)
        stdout.puts("[#{job.number}]")
        success
      end
    end
  end
end
