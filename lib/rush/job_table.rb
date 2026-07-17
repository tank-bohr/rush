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
  # environments keep the entries only as unwaitable display copies
  # (POSIX 2.12 — see #enter_subshell).
  class JobTable
    extend T::Sig

    sig { params(system: SystemCalls).void }
    def initialize(system)
      @system = system
      @jobs = T.let(
        {}, #: Hash[Integer, Job]
        T::Hash[Integer, Job]
      )
      @stash = T.let(
        {}, #: Hash[Integer, Process::Status]
        T::Hash[Integer, Process::Status]
      )
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
    sig { params(pid: Integer, text: T.nilable(String)).void }
    def record(pid, text: nil)
      @jobs[pid] = Job.new(free_number, pid, text: text) if pid.positive?
    end

    # A foreground job a WUNTRACED wait handed back as stopped (^Z): it
    # becomes a job-table entry — number, the group leader as its pid, every
    # pipeline member listed — parked Stopped, where jobs/wait/kill/%ids
    # find it (dash keeps its jobtab entry; rush creates one on the spot).
    sig { params(pids: T::Array[Integer], stopsig: Integer, text: T.nilable(String)).void }
    def adopt_stopped(pids, stopsig, text = nil)
      leader = pids.fetch(0)
      (@jobs[leader] ||= Job.new(free_number, leader, members: pids, text: text)).stop(stopsig) if leader.positive?
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
    # live job, or nil when the pid is not a waitable job here — unknown,
    # or a fork-inherited display copy (POSIX: 127).
    sig { params(pid: Integer).returns(T.nilable(Status)) }
    def wait_for(pid)
      @jobs[pid]&.harvest { settle(pid) }
    rescue Errno::ECHILD
      Status.success
    end

    # A forked child environment is a duplicate of the shell environment
    # (POSIX 2.12), async pids included: the entries stay for display —
    # jobs, jobs -p, and through them the standard-blessed `wait $(jobs -p)`
    # in the parent — but demoted to inherited copies, since the parent's
    # children are not waitable here: wait by pid reports 127 and a %id
    # reports No such job, as dash does in a real (non-tail-optimized)
    # forked child. It is no root shell either (see #root?).
    sig { void }
    def enter_subshell
      @jobs.each_value(&:inherit)
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
      while (reaped = @control.monitor? ? @system.poll_stopped : @system.poll_child)
        store(reaped.first, reaped.last)
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

    # dash's cmdloop showjobs(SHOW_CHANGED): the Repl calls this before
    # each PS1 under monitor mode.
    sig { params(out: T.untyped).void }
    def announce_changed(out)
      poll
      ordered.select(&:changed).each { |job| job.report(self, out) }
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

    # A relayed stop (StopRelay: armed stage, stopped target) re-raises
    # onto this process and, after SIGCONT, re-waits the same target.
    sig { params(target: Integer).returns(Process::Status) }
    def reap_raw(target)
      loop do
        pid, status = reap_one(target)
        return status if pid == target && !StopRelay.relay?(@control, status)

        pid == target ? StopRelay.raise_onto_self(@system, status) : store(pid, status)
      end
    end

    # waitpid(-1) only when a background job could change state meanwhile —
    # a stopped job still counts, its death arrives asynchronously, but an
    # inherited display copy never does (not this environment's child) —
    # since the direct form cannot reap a foreign child; the plain
    # foreground path stays byte-identical to the pre-table behaviour.
    # Monitor mode and an armed stage relay wait WUNTRACED (dash: mflag),
    # so a stop answers instead of hanging the shell.
    sig { params(target: Integer).returns([Integer, Process::Status]) }
    def reap_one(target)
      pid = @jobs.each_value.any? { |job| !job.finished? && !job.inherited? } ? -1 : target
      @control.stoppable_waits? ? @system.wait_stoppable(pid) : @system.waitpid2(pid)
    end

    # Job#finish answers non-nil, so a known pid never falls to the stash.
    sig { params(pid: Integer, status: Process::Status).void }
    def store(pid, status)
      @jobs[pid]&.finish(status) || (@stash[pid] = status)
    end
  end
end
