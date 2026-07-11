# typed: true
# frozen_string_literal: true

module Rush
  # The armed stage relay (rush-l4o): a pipeline stage of a monitor-mode job
  # is a transparent member of it — a stop its own foreground wait reaps is
  # re-raised onto the stage process itself, so the job's owner sees the
  # member stop; after fg/bg's SIGCONT the reap loop re-waits the same
  # target. dash reaches the same picture by exec-ing simple stages in
  # place. Methods are explicit singletons, like Signals.
  module StopRelay
    extend T::Sig

    # The reaped target's stop should be re-raised: relay armed AND the
    # status is a stop (deaths and exits pass through untouched).
    sig { params(control: JobTable::Control, status: Process::Status).returns(T::Boolean) }
    def self.relay?(control, status)
      control.relay? && status.stopped?
    end

    # Default disposition first — the -m parent left TSTP/TTOU ignored,
    # while SIGSTOP takes no disposition and cannot be trapped — then the
    # stop signal onto this very process. The block never runs: the
    # command string wins inside trap_signal, as TrapRunner's ignores do.
    sig { params(system: SystemCalls, status: Process::Status).void }
    def self.raise_onto_self(system, status)
      name = Signals::NUMBERS.fetch(T.must(status.stopsig))
      system.trap_signal(name, 'SYSTEM_DEFAULT') { nil } unless name == 'STOP'
      system.kill(name, system.pid)
    end
  end
end
