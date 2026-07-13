# typed: true
# frozen_string_literal: true

module Rush
  # Reopens the table only to keep its interruptible-wait implementation next
  # to the polling collaborator; the core initializer owns these ivars.
  # :reek:InstanceVariableAssumption
  class JobTable
    # WNOHANG polling used only by the wait builtin. Foreground awaits remain
    # blocking, while a caught trap can stop this wait without reaping its job.
    class InterruptibleWait
      extend T::Sig

      POLL_INTERVAL = 0.01

      sig do
        params(system: SystemCalls, control: Control, target: Integer,
               pending: T.proc.returns(T.nilable(Integer))).void
      end
      def initialize(system, control, target, pending)
        @system = system
        @control = control
        @target = target
        @pending = pending
      end

      sig { returns(T.any(Process::Status, Status)) }
      def call
        loop do
          result = interrupted || poll
          return result if result

          sleep(POLL_INTERVAL)
        end
      end

      private

      sig { returns(T.nilable(Status)) }
      def interrupted
        code = @pending.call
        Status.new(code) if code
      end

      sig { returns(T.nilable(Process::Status)) }
      def poll
        pair = @control.stoppable_waits? ? @system.poll_pid_stopped(@target) : @system.poll_pid(@target)
        pair&.fetch(1)
      end
    end

    # The wait builtin alone is interruptible by a caught signal. Polling keeps
    # JobTable the sole reaper while foreground await remains a blocking wait.
    sig { params(pid: Integer, pending: T.proc.returns(T.nilable(Integer))).returns(T.nilable(Status)) }
    def wait_for_interruptibly(pid, &pending)
      @jobs[pid]&.harvest { interruptible_settle(pid, pending) }
    rescue Errno::ECHILD
      Status.success
    end

    private

    sig do
      params(pid: Integer, pending: T.proc.returns(T.nilable(Integer))).returns(T.any(Process::Status, Status))
    end
    def interruptible_settle(pid, pending)
      @stash.delete(pid) || InterruptibleWait.new(@system, @control, pid, pending).call
    end
  end
end
