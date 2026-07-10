# typed: true
# frozen_string_literal: true

module Rush
  class JobTable
    # One job: its [n] number, the pid the shell tracks (a pipeline's group
    # leader, pids.first; members lists every process, for fg/bg and group
    # kills), its origin (only a job created under monitor mode may be
    # resumed — dash's per-job jobctl bit, probed across set -m/+m flips),
    # and its state, held as the Status of the last decisive wait: nothing
    # while running, a stop-carrying Status while parked (^Z — re-waitable,
    # answering 128+stopsig until fg/bg's SIGCONT resumes it), a final one
    # once done. The wait builtin reads #status; jobs prints #display_state.
    class Job
      extend T::Sig

      sig { returns(Integer) }
      attr_reader :number

      sig { returns(T::Array[Integer]) }
      attr_reader :members

      sig { params(number: Integer, pid: Integer, members: T::Array[Integer], origin: Symbol).void }
      def initialize(number, pid, members: [pid], origin: :plain)
        @number = number
        @members = members
        @origin = origin
        @result = T.let(nil, T.nilable(Status))
      end

      sig { returns(Integer) }
      def pid
        @members.fetch(0)
      end

      # Created under monitor mode, so fg/bg may resume it (dash refuses
      # "not created under job control" for the rest, whatever mflag says
      # now — probed).
      sig { returns(T::Boolean) }
      def controlled?
        @origin == :monitored
      end

      # File a reaped wait result: a stop parks the job (still alive, still
      # re-waitable), anything else settles it for good; answers the filed
      # Status (never nil — JobTable#store leans on that).
      sig { params(raw: Process::Status).returns(Status) }
      def finish(raw)
        @result = Status.of(raw)
      end

      sig { params(stopsig: Integer).void }
      def stop(stopsig)
        @result = Status.stopped(stopsig)
      end

      # fg/bg's SIGCONT: a stopped job runs again; settled ones stay put.
      sig { void }
      def resume
        @result = nil if stopped?
      end

      # The whole fg/bg resume move: mark the job running again and SIGCONT
      # its process group (the leader pid is the group under job control); a
      # group already gone is settled — the memory answers.
      sig { params(system: SystemCalls).void }
      def continue(system)
        resume
        system.kill('CONT', -pid)
      rescue Errno::ESRCH
        nil
      end

      # Reap once: a settled job answers from memory (dash never frees an
      # entry on wait), a stopped one answers 128+stopsig immediately and
      # repeatably (dash-probed), and a running one blocks in the supplied
      # wait — which may itself park the job.
      sig { params(blk: T.proc.returns(Process::Status)).returns(Status) }
      def harvest(&blk)
        finish(yield) if running?
        status
      end

      sig { returns(T::Boolean) }
      def running?
        !@result
      end

      sig { returns(T::Boolean) }
      def stopped?
        !!@result&.stopped?
      end

      sig { returns(T::Boolean) }
      def finished?
        !running? && !stopped?
      end

      sig { returns(T.nilable(Integer)) }
      def stopsig
        @result&.stopsig
      end

      sig { returns(Status) }
      def status
        T.must(@result)
      end

      # The state column of the jobs listing (dash's statusfmt vocabulary):
      # Running, a strsignal Stopped flavour, Done/Done(n), or the killing
      # signal's description.
      sig { returns(String) }
      def display_state
        result = @result
        return 'Running' unless result
        return Signals.stop_description(T.must(result.stopsig)) if result.stopped?

        settled_state(result)
      end

      private

      sig { params(result: Status).returns(String) }
      def settled_state(result)
        signal = result.termsig
        return Signals.description(signal) if signal

        code = result.exitstatus
        code.zero? ? 'Done' : "Done(#{code})"
      end
    end
  end
end
