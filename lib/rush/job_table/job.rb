# typed: true
# frozen_string_literal: true

module Rush
  class JobTable
    # One job. Identity holds what never changes: the [n] number, the member
    # pids (a pipeline's group leader first — fg/bg and group kills need them
    # all), and the rendered command text — nil outside job control, exactly
    # dash's model, where cmdtext is kept only for jobctl jobs and that
    # absence IS the fg/bg "not created under job control" refusal.
    # State is the Status of the last decisive wait: nothing while running, a
    # stop-carrying Status while parked (^Z — re-waitable, answering
    # 128+stopsig until fg/bg's SIGCONT), a final one once done; `changed`
    # tracks whether the latest transition has been reported (the pre-prompt
    # notification, or the jobs listing itself).
    class Job
      extend T::Sig

      # The creation-time facts, bundled so the mutable state stays apart.
      class Identity
        extend T::Sig

        sig { returns(Integer) }
        attr_reader :number

        sig { returns(T::Array[Integer]) }
        attr_reader :members

        sig { returns(T.nilable(String)) }
        attr_reader :text

        sig { params(number: Integer, members: T::Array[Integer], text: T.nilable(String)).void }
        def initialize(number, members, text)
          @number = number
          @members = members
          @text = text
        end
      end

      sig { returns(T::Boolean) }
      attr_reader :changed

      sig { params(number: Integer, pid: Integer, members: T::Array[Integer], text: T.nilable(String)).void }
      extend Forwardable

      def initialize(number, pid, members: [pid], text: nil)
        @identity = T.let(Identity.new(number, members, text), Identity)
        @result = T.let(nil, T.nilable(Status))
        @changed = T.let(false, T::Boolean)
      end

      def_delegators :@identity, :number, :members

      sig { returns(Integer) }
      def pid
        members.fetch(0)
      end

      # The rendered command line ('' outside job control, where dash keeps
      # no text either).
      sig { returns(String) }
      def text
        @identity.text.to_s
      end

      # Created under monitor mode, so fg/bg may resume it (dash refuses
      # "not created under job control" for the rest, whatever mflag says
      # now — probed): the kept command text is the stamp.
      sig { returns(T::Boolean) }
      def controlled?
        !!@identity.text
      end

      # File a reaped wait result: a stop parks the job (still alive, still
      # re-waitable), anything else settles it for good; answers the filed
      # Status (never nil — JobTable#store leans on that).
      sig { params(raw: Process::Status).returns(Status) }
      def finish(raw)
        @changed = true
        @result = Status.of(raw)
      end

      sig { params(stopsig: Integer).void }
      def stop(stopsig)
        @changed = true
        @result = Status.stopped(stopsig)
      end

      # fg/bg's SIGCONT: a stopped job runs again — its own announcement, no
      # notification owed.
      sig { void }
      def resume
        return unless stopped?

        @result = nil
        @changed = false
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

      # A state change was displayed (jobs listing or pre-prompt
      # notification): nothing further to announce.
      sig { void }
      def reported
        @changed = false
      end

      # One pre-prompt notification: print this job's change and settle the
      # report — a finished entry leaves the table (dash's showjob + free).
      sig { params(table: JobTable, out: T.untyped).void }
      def report(table, out)
        out.puts(JobReport.line(table, self))
        reported
        table.forget(self) if finished?
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
