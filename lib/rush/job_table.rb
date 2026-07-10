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

    # One asynchronous job: its [n] number, pid, and — once reaped — the raw
    # Process::Status: the wait builtin derives $? from it, and the jobs
    # builtin renders Done(n) or a signal description.
    class Job
      extend T::Sig

      sig { returns(Integer) }
      attr_reader :number

      sig { returns(Integer) }
      attr_reader :pid

      sig { returns(T.nilable(Process::Status)) }
      attr_reader :raw

      sig { params(number: Integer, pid: Integer).void }
      def initialize(number, pid)
        @number = number
        @pid = pid
        @raw = T.let(nil, T.nilable(Process::Status))
      end

      sig { params(raw: Process::Status).void }
      def finish(raw)
        @raw = raw
      end

      # Reap once: the first harvest fills raw from the supplied wait;
      # repeats answer from memory (dash never frees an entry on wait).
      sig { params(blk: T.proc.returns(Process::Status)).returns(Status) }
      def harvest(&blk)
        @raw ||= yield
        status
      end

      sig { returns(T::Boolean) }
      def running?
        !@raw
      end

      sig { returns(Status) }
      def status
        Status.of(T.must(@raw))
      end
    end

    sig { params(system: SystemCalls).void }
    def initialize(system)
      @system = system
      @jobs = T.let({}, T::Hash[Integer, Job])
      @stash = T.let({}, T::Hash[Integer, Process::Status])
    end

    # A background launch: the pid becomes job [n] — the lowest free number,
    # as dash numbers slots. Fake fork ports return no child pid (mapped to
    # 0); a real parent always records a positive one.
    sig { params(pid: Integer).void }
    def record(pid)
      return unless pid.positive?

      @jobs[pid] = Job.new(free_number, pid)
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

    # The wait builtin, no operands: collect every known background job.
    sig { void }
    def wait_all
      @jobs.each_key { |pid| wait_for(pid) }
    end

    # A forked child environment starts with no jobs of its own (POSIX 2.12):
    # the parent's children are not waitable here — wait by pid reports 127
    # and a %id reports No such job, as dash does in a real (non-tail-
    # optimized) subshell.
    sig { void }
    def clear_for_subshell
      @jobs.clear
      @stash.clear
    end

    # The jobs builtin, after displaying a finished entry: dash frees
    # reported jobs, so a later wait or %id no longer knows them.
    sig { params(job: Job).void }
    def forget(job)
      @jobs.delete(job.pid)
    end

    # Opportunistic non-blocking reap, so the jobs builtin sees a child that
    # finished since the last synchronous wait.
    sig { void }
    def poll
      while (reaped = @system.poll_child)
        store(reaped.fetch(0), reaped.fetch(1))
      end
    rescue Errno::ECHILD
      nil
    end

    private

    sig { params(pid: Integer).returns(Process::Status) }
    def settle(pid)
      @stash.delete(pid) || reap_raw(pid)
    end

    sig { returns(Integer) }
    def free_number
      taken = @jobs.each_value.map(&:number)
      number = 1
      number += 1 while taken.include?(number)
      number
    end

    sig { params(target: Integer).returns(Process::Status) }
    def reap_raw(target)
      loop do
        pid, status = reap_one(target)
        return status if pid == target

        store(pid, status)
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
      @jobs.each_value.any?(&:running?)
    end

    sig { params(pid: Integer, status: Process::Status).void }
    def store(pid, status)
      job = @jobs[pid]
      job ? job.finish(status) : (@stash[pid] = status)
    end
  end
end
