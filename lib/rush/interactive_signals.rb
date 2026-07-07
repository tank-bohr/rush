# typed: true
# frozen_string_literal: true

module Rush
  # The interactive shell's default signal dispositions (POSIX: "ignored in a
  # manner that allows trap to work"; dash is the oracle): SIGINT interrupts
  # the current line — its handler raises Interrupted, which the session turns
  # into $?=130 and a fresh prompt — while SIGQUIT and SIGTERM are swallowed by
  # no-op handlers. All three are handler blocks rather than SIG_IGN, so
  # children spawned via exec revert to the OS defaults. `trap` overrides
  # them; `trap -` and subshells restore through TrapRunner's base table.
  class InteractiveSignals
    extend T::Sig

    # Non-lambda procs: Signal.trap calls handlers with the signal number, and
    # a strict lambda would die on the extra argument.
    sig { params(executor: Executor).void }
    def self.install(executor)
      executor.trap_runner.install_base(
        'INT' => proc { raise Interrupted, 'interrupted' },
        'QUIT' => proc {},
        'TERM' => proc {}
      )
    end
  end
end
