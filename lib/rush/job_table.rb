# typed: true
# frozen_string_literal: true

module Rush
  # The single owner of child reaping (the design risk epic rush-mv8 recorded):
  # every synchronous wait routes through #await, so no two waits can steal
  # each other's statuses. While no background job is running an await targets
  # its pid directly; once an asynchronous list has launched, it reaps
  # whichever child exits next and files foreign statuses — a background job's
  # under its pid (where the wait builtin finds it), a sibling foreground
  # child's in a stash its own await consults first. Background statuses stay
  # remembered after reaping, so repeated `wait $pid` keeps answering
  # (dash-verified).
  class JobTable
    extend T::Sig

    sig { params(system: SystemCalls).void }
    def initialize(system)
      @system = system
      @jobs = T.let({}, T::Hash[Integer, T.any(Symbol, Status)])
      @stash = T.let({}, T::Hash[Integer, Status])
    end

    # A background launch: the pid becomes known to the wait builtin. Fake fork
    # ports return no child pid (mapped to 0); a real parent always records a
    # positive one.
    sig { params(pid: Integer).void }
    def record(pid)
      @jobs[pid] = :running if pid.positive?
    end

    # Blocking wait for a foreground child's status. Waiting in a subshell for
    # a job launched before the fork raises ECHILD — the job is the parent's
    # child, not ours; dash reports success there.
    sig { params(pid: Integer).returns(Status) }
    def await(pid)
      @stash.delete(pid) || reap_until(pid)
    rescue Errno::ECHILD
      Status.success
    end

    # The wait builtin, one pid: a remembered status, a blocking wait on a live
    # background job, or nil when the pid is not a known child (POSIX: 127).
    sig { params(pid: Integer).returns(T.nilable(Status)) }
    def wait_for(pid)
      job = @jobs[pid]
      return job if job.is_a?(Status)
      return unless job

      @jobs[pid] = await(pid)
    end

    # The wait builtin, no operands: collect every known background job.
    sig { void }
    def wait_all
      @jobs.each_key { |pid| wait_for(pid) }
    end

    private

    sig { params(target: Integer).returns(Status) }
    def reap_until(target)
      loop do
        pid, status = reap_one(target)
        return Status.of(status) if pid == target

        store(pid, Status.of(status))
      end
    end

    # waitpid(-1) only when a background job could exit meanwhile; the direct
    # form cannot reap a foreign child, keeping the plain foreground path
    # byte-identical to the pre-table behaviour.
    sig { params(target: Integer).returns([Integer, Process::Status]) }
    def reap_one(target)
      @system.waitpid2(background_running? ? -1 : target)
    end

    sig { returns(T::Boolean) }
    def background_running?
      @jobs.value?(:running)
    end

    sig { params(pid: Integer, status: Status).void }
    def store(pid, status)
      if @jobs.key?(pid)
        @jobs[pid] = status
      else
        @stash[pid] = status
      end
    end
  end
end
