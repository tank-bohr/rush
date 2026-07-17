# typed: true
# frozen_string_literal: true

module Rush
  class SystemCalls
    # Child-process control for the job machinery, mixed into SystemCalls:
    # reaping (JobTable is the sole consumer), process grouping, terminal
    # handover (tcsetpgrp/tcgetpgrp via IO#ioctl), and the platform gate.
    # Inline boundary contracts deliberately make this syscall port longer than the quality default.
    # rubocop:disable Metrics/ModuleLength
    module ProcessControl
      extend T::Sig

      # ioctl request codes for tcgetpgrp/tcsetpgrp, keyed on the build's
      # host_os: Ruby exposes no tc[gs]etpgrp, but IO#ioctl is core and the
      # codes are stable ABI constants — the asm-generic pair on Linux, the
      # sizeof-encoded form on darwin and the BSDs. An unmatched Unix gets
      # no codes: tcgetpgrp answers nil, the terminal is never acquired, and
      # job control degrades to grouping-only (the epic's Fiddle-into-libc
      # fallback was judged not worth a dependency for platforms rush cannot
      # test; revisit if one materialises).
      TIOCGPGRP = T.let({ linux: 0x540F, bsd: 0x40047477 }.freeze, T::Hash[Symbol, Integer])
      TIOCSPGRP = T.let({ linux: 0x5410, bsd: 0x80047476 }.freeze, T::Hash[Symbol, Integer])
      TERMINAL_FAMILIES = T.let({ /linux/ => :linux, /darwin|bsd|dragonfly/ => :bsd }.freeze,
                                T::Hash[Regexp, Symbol])

      # EINTR-style retry: an interactive SIGINT raises Interrupted at a safe
      # point inside the blocking wait; the child is dying from the same signal,
      # so wait again and reap it rather than leaking a zombie.
      sig { params(pid: Integer).returns([Integer, Process::Status]) }
      def waitpid2(pid)
        T.must(Process.waitpid2(pid))
      rescue Interrupted
        retry
      end

      # The monitor-mode blocking wait (rush-mv8.4): WUNTRACED also returns a
      # child the terminal (or a kill) has STOPPED, so ^Z hands control back
      # to the shell instead of hanging it — dash waits this way whenever
      # mflag is on, interactive or not (probed: $? = 148 off-tty too).
      sig { params(pid: Integer).returns([Integer, Process::Status]) }
      def wait_stoppable(pid)
        T.must(Process.waitpid2(pid, Process::WUNTRACED))
      rescue Interrupted
        retry
      end

      # Non-blocking reap of any finished child: [pid, status], or nil while
      # children exist but none has exited. Raises ECHILD, like waitpid2, when
      # there are no children at all.
      sig { returns(T.nilable([Integer, Process::Status])) }
      def poll_child
        Process.waitpid2(-1, Process::WNOHANG)
      end

      sig { params(pid: Integer).returns(T.nilable([Integer, Process::Status])) }
      def poll_pid(pid)
        Process.waitpid2(pid, Process::WNOHANG)
      end

      # The monitor-mode poll (pairs with wait_stoppable as poll_child pairs
      # with waitpid2): WUNTRACED, so the jobs builtin also sees a background
      # job freshly SIGSTOPped since the last wait.
      sig { returns(T.nilable([Integer, Process::Status])) }
      def poll_stopped
        Process.waitpid2(-1, Process::WNOHANG | Process::WUNTRACED)
      end

      sig { params(pid: Integer).returns(T.nilable([Integer, Process::Status])) }
      def poll_pid_stopped(pid)
        Process.waitpid2(pid, Process::WNOHANG | Process::WUNTRACED)
      end

      # Place a process into a process group (pid 0 = the caller, pgid 0 = its
      # own pid): the grouping seam. Failure means the double-setpgid race was
      # lost benignly — EACCES: the child already exec'd (its own setpgid won);
      # ESRCH/EPERM: it already exited — so the group is settled either way and
      # the error is swallowed, as dash void-casts the same call.
      # :nocov:
      sig { params(pid: Integer, pgid: Integer).void }
      def setpgid(pid, pgid)
        Process.setpgid(pid, pgid)
      rescue Errno::EACCES, Errno::ESRCH, Errno::EPERM
        nil
      end

      # Fork a child directly into a process group (pgid 0 = the child's own
      # pid, per POSIX, so the kernel does the leader/joiner defaulting): the
      # double setpgid, issued on both sides of the fork, means whichever side
      # runs first settles the group before the child can exec or the parent
      # can wait — the same dance as dash's forkchild/forkparent. A foreground
      # job leader is also handed the terminal (tty given), child-side before
      # the body runs, exactly where dash's forkchild calls xtcsetpgrp — so
      # the job can never touch the tty before it owns it.
      sig do
        params(group: Integer, tty: T.nilable(IO), child_main: T.proc.void).returns(T.nilable(Integer))
      end
      def fork_grouped(group, tty = nil, &child_main)
        pid = T.cast(self, SystemCalls).fork { grouped_child(group, tty, &child_main) }
        setpgid(pid, group) if pid
        pid
      end

      sig { params(group: Integer, tty: T.nilable(IO), block: T.proc.void).void }
      def grouped_child(group, tty, &block)
        setpgid(0, group)
        tcsetpgrp(tty, Process.pid) if tty
        block.call # rubocop:disable Performance/RedundantBlockCall -- preserve the checked Proc contract
      end

      # The controlling terminal, for handing between process groups:
      # /dev/tty when the process has one, else a duplicate of the first
      # standard stream that is a tty (dash walks fds 2..0 the same way; the
      # dup means the caller always owns — and closes — its handle, immune
      # to later redirections of the original). nil without a terminal.
      sig { returns(T.nilable(IO)) }
      def open_tty
        File.open('/dev/tty', 'r+')
      rescue SystemCallError
        streams = T.let([$stderr, $stdout, $stdin], T::Array[IO])
        streams.find(&:tty?)&.dup
      end

      # The terminal's foreground process group, or nil when the fd is not a
      # tty or the platform has no known request code: dash's setjobctl uses
      # the same call as the "can we do the tty dance at all" probe.
      sig { params(tty: IO).returns(T.nilable(Integer)) }
      def tcgetpgrp(tty)
        family = terminal_family
        read_pgrp(tty, TIOCGPGRP.fetch(family)) if family
      end

      sig { params(tty: IO, request: Integer).returns(T.nilable(Integer)) }
      def read_pgrp(tty, request)
        buffer = [0].pack('l')
        tty.ioctl(request, buffer)
        Kernel.Integer(buffer.unpack1('l'))
      rescue SystemCallError, IOError
        nil
      end

      # Hand the terminal to a process group. The caller's group often does
      # not own the terminal at that moment (reclaiming after a foreground
      # job): the kernel answers such an ioctl with SIGTTOU, and a caught
      # handler would abort it with EINTR while a default disposition would
      # stop the shell — so the signal is ignored for real (SIG_IGN, not a
      # handler block) for the call's duration, as dash holds TTOU ignored
      # around xtcsetpgrp. Failure (the group already dead, the fd revoked)
      # is swallowed like setpgid's: the reclaim that follows every
      # foreground job settles ownership either way.
      sig { params(tty: IO, pgid: Integer).void }
      def tcsetpgrp(tty, pgid)
        family = terminal_family
        return unless family

        ignoring_ttou { tty.ioctl(TIOCSPGRP.fetch(family), [pgid].pack('l')) }
      rescue SystemCallError, IOError
        nil
      end
      # :nocov:

      # Job control needs POSIX process groups, which Windows builds lack (the
      # rush-mv8 platform gate); everywhere else Process.setpgid is real.
      sig { returns(T::Boolean) }
      def job_control_supported?
        !host_os.match?(/mswin|mingw|cygwin/)
      end

      # Which ioctl vocabulary this build speaks.
      sig { returns(T.nilable(Symbol)) }
      def terminal_family
        TERMINAL_FAMILIES.find { |pattern, _family| host_os.match?(pattern) }&.last
      end

      private

      sig { returns(String) }
      def host_os
        T.let(RbConfig::CONFIG.fetch('host_os'), String)
      end

      # :nocov:
      sig do
        type_parameters(:U)
          .params(block: T.proc.returns(T.type_parameter(:U)))
          .returns(T.type_parameter(:U))
      end
      def ignoring_ttou(&block)
        previous = Signal.trap('TTOU', 'IGNORE')
        block.call # rubocop:disable Performance/RedundantBlockCall -- preserve the generic return type
      ensure
        Signal.trap('TTOU', previous || 'DEFAULT')
      end
      # :nocov:
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
