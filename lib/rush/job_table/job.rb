# typed: true
# frozen_string_literal: true

module Rush
  class JobTable
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
  end
end
