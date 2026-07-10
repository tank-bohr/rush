# typed: true
# frozen_string_literal: true

module Rush
  class JobTable
    # One job: its [n] number, the pid the shell tracks (a pipeline's group
    # leader, pids.first; members lists every process, for fg/bg and group
    # kills), and its state. Running until a wait says otherwise; a WUNTRACED
    # wait can park it Stopped (^Z) — re-waitable, answering 128+stopsig
    # meanwhile — and a final status makes it Done: the wait builtin derives
    # $? from raw, and the jobs builtin prints #display_state.
    class Job
      extend T::Sig

      sig { returns(Integer) }
      attr_reader :number

      sig { returns(T::Array[Integer]) }
      attr_reader :members

      sig { returns(T.nilable(Process::Status)) }
      attr_reader :raw

      sig { returns(T.nilable(Integer)) }
      attr_reader :stopsig

      sig { params(number: Integer, pid: Integer, members: T::Array[Integer]).void }
      def initialize(number, pid, members: [pid])
        @number = number
        @members = members
        @raw = T.let(nil, T.nilable(Process::Status))
        @stopsig = T.let(nil, T.nilable(Integer))
      end

      sig { returns(Integer) }
      def pid
        @members.fetch(0)
      end

      # File a reaped wait result: a stop parks the job (still alive, still
      # re-waitable), anything else settles it for good.
      sig { params(raw: Process::Status).void }
      def finish(raw)
        raw.stopped? ? stop(T.must(raw.stopsig)) : (@raw = raw)
      end

      sig { params(stopsig: Integer).void }
      def stop(stopsig)
        @stopsig = stopsig
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
        !@raw && !@stopsig
      end

      sig { returns(T::Boolean) }
      def stopped?
        !@raw && !!@stopsig
      end

      sig { returns(T::Boolean) }
      def finished?
        !!@raw
      end

      sig { returns(Status) }
      def status
        raw = @raw
        raw ? Status.of(raw) : Status.stopped(T.must(@stopsig))
      end

      # The state column of the jobs listing (dash's statusfmt vocabulary):
      # Running, a strsignal Stopped flavour, Done/Done(n), or the killing
      # signal's description.
      sig { returns(String) }
      def display_state
        return 'Running' if running?
        return Signals.stop_description(T.must(@stopsig)) if stopped?

        settled_state
      end

      private

      sig { returns(String) }
      def settled_state
        signal = T.must(@raw).termsig
        signal ? Signals.description(signal) : done_state
      end

      sig { returns(String) }
      def done_state
        code = T.must(T.must(@raw).exitstatus)
        code.zero? ? 'Done' : "Done(#{code})"
      end
    end
  end
end
