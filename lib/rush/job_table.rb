# typed: true
# frozen_string_literal: true

module Rush
  # The shell's asynchronous jobs, and the single owner of child reaping (the
  # design risk epic rush-mv8 recorded): every synchronous wait routes through
  # #await, so no two waits can steal each other's statuses. While no
  # background job is running an await targets its pid directly; once an
  # asynchronous list has launched, it reaps whichever child exits next and
  # files foreign statuses — a background job's on its entry (where the wait
  # builtin finds it), a sibling foreground child's in a stash its own await
  # consults first. A reaped job's status stays remembered until the jobs
  # builtin displays it (dash frees reported entries); forked child
  # environments start with no jobs at all.
  class JobTable
    extend T::Sig

    sig { params(system: SystemCalls).void }
    def initialize(system)
      @system = system
      @jobs = T.let({}, T::Hash[Integer, Job])
      @stash = T.let({}, T::Hash[Integer, Process::Status])
      @control = T.let(Control.new, Control)
    end

    # The durable job-control environment (root-shell bit, acquired
    # terminal): JobControl's state, kept here because it lives and dies
    # with the table — a forked child drops both together.
    sig { returns(Control) }
    attr_reader :control

    # A background launch: the pid becomes job [n] — the lowest free number,
    # as dash numbers slots. Fake fork ports return no child pid (mapped to
    # 0); a real parent always records a positive one.
    sig { params(pid: Integer).void }
    def record(pid)
      @jobs[pid] = Job.new(free_number, pid, origin: @control.origin) if pid.positive?
    end

    # A foreground job a WUNTRACED wait handed back as stopped (^Z): it
    # becomes a job-table entry — number, the group leader as its pid, every
    # pipeline member listed — parked Stopped, where jobs/wait/kill/%ids
    # find it (dash keeps its jobtab entry; rush creates one on the spot).
    sig { params(pids: T::Array[Integer], stopsig: Integer).void }
    def adopt_stopped(pids, stopsig)
      leader = pids.fetch(0)
      return unless leader.positive?

      (@jobs[leader] ||= Job.new(free_number, leader, members: pids, origin: @control.origin)).stop(stopsig)
    end

    # Newest first: the jobs builtin's display order, and what makes the
    # first entry the current job (+) and the second the previous one (-).
    sig { returns(T::Array[Job]) }
    def ordered
      @jobs.values.reverse
    end

    sig { returns(T.nilable(Job)) }
    def current
      ordered.first
    end

    sig { returns(T.nilable(Job)) }
    def previous
      ordered.fetch(1, nil)
    end

    sig { params(number: Integer).returns(T.nilable(Job)) }
    def numbered(number)
      @jobs.each_value.find { |job| job.number == number }
    end

    # Blocking wait for a foreground child's status. ECHILD is a defensive
    # guard: entries never outlive their environment (forked children clear
    # the table), so a wait on a vanished child answers success rather than
    # crashing.
    sig { params(pid: Integer).returns(Status) }
    def await(pid)
      Status.of(settle(pid))
    rescue Errno::ECHILD
      Status.success
    end

    # The wait builtin, one pid: a remembered status, a blocking wait on a
    # live job, or nil when the pid is not a known job (POSIX: 127).
    sig { params(pid: Integer).returns(T.nilable(Status)) }
    def wait_for(pid)
      @jobs[pid]&.harvest { settle(pid) }
    rescue Errno::ECHILD
      Status.success
    end

    # A forked child environment starts with no jobs of its own (POSIX 2.12):
    # the parent's children are not waitable here — wait by pid reports 127
    # and a %id reports No such job, as dash does in a real (non-tail-
    # optimized) subshell. It is no root shell either (see #root?).
    sig { void }
    def clear_for_subshell
      @jobs.clear
      @stash.clear
      @control.fork_child
    end

    # The jobs builtin, after displaying a finished entry: dash frees
    # reported jobs, so a later wait or %id no longer knows them.
    sig { params(job: Job).void }
    def forget(job)
      @jobs.delete(job.pid)
    end

    # Opportunistic non-blocking reap, so the jobs builtin sees a child that
    # finished — or, under monitor mode, stopped — since the last
    # synchronous wait.
    sig { void }
    def poll
      while (reaped = @control.monitor ? @system.poll_stopped : @system.poll_child)
        store(reaped.fetch(0), reaped.fetch(1))
      end
    rescue Errno::ECHILD
      nil
    end

    # fg's wait (rush-mv8.5): every member — the leader through its entry,
    # the rest through the stash-aware await — the verdict carrying any
    # stop, exactly like a fresh foreground pipeline's.
    sig { params(job: Job).returns(Status) }
    def settle_members(job)
      PipelineStatuses.new(job.members.map { |pid| wait_for(pid) || await(pid) }).verdict
    end

    # The exit builtin with a stopped job: refused with "You have stopped
    # jobs." exactly once (the Control's dash-job_warning window).
    sig { returns(T::Boolean) }
    def refuse_exit?
      @jobs.each_value.any?(&:stopped?) && @control.warn_exit?
    end

    private

    sig { params(pid: Integer).returns(Process::Status) }
    def settle(pid)
      @stash.delete(pid) || reap_raw(pid)
    end

    # The lowest free job number, as dash fills slots: the range up to
    # size+1 always contains one.
    sig { returns(Integer) }
    def free_number
      ((1..(@jobs.size + 1)).to_a - @jobs.each_value.map(&:number)).fetch(0)
    end

    sig { params(target: Integer).returns(Process::Status) }
    def reap_raw(target)
      loop do
        pid, status = reap_one(target)
        return status if pid == target

        store(pid, status)
      end
    end

    # waitpid(-1) only when a background job could change state meanwhile —
    # a stopped job still counts, its death arrives asynchronously — since
    # the direct form cannot reap a foreign child; the plain foreground path
    # stays byte-identical to the pre-table behaviour. Monitor mode waits
    # WUNTRACED (dash: mflag), so ^Z answers instead of hanging the shell.
    sig { params(target: Integer).returns([Integer, Process::Status]) }
    def reap_one(target)
      pid = @jobs.each_value.any? { |job| !job.finished? } ? -1 : target
      @control.monitor ? @system.wait_stoppable(pid) : @system.waitpid2(pid)
    end

    # Job#finish answers non-nil, so a known pid never falls to the stash.
    sig { params(pid: Integer, status: Process::Status).void }
    def store(pid, status)
      @jobs[pid]&.finish(status) || (@stash[pid] = status)
    end
  end
end
