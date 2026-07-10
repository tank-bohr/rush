# typed: false
# frozen_string_literal: true

module Rush
  class SystemCalls
    # Child-process control for the job machinery, mixed into SystemCalls:
    # reaping (JobTable is the sole consumer), process grouping, and the
    # platform gate; the terminal-handover slice (rush-mv8.3) adds
    # tcsetpgrp/tcgetpgrp here.
    module ProcessControl
      # EINTR-style retry: an interactive SIGINT raises Interrupted at a safe
      # point inside the blocking wait; the child is dying from the same signal,
      # so wait again and reap it rather than leaking a zombie.
      def waitpid2(pid)
        Process.waitpid2(pid)
      rescue Interrupted
        retry
      end

      # Non-blocking reap of any finished child: [pid, status], or nil while
      # children exist but none has exited. Raises ECHILD, like waitpid2, when
      # there are no children at all.
      def poll_child
        Process.waitpid2(-1, Process::WNOHANG)
      end

      # Place a process into a process group (pid 0 = the caller, pgid 0 = its
      # own pid): the grouping seam. Failure means the double-setpgid race was
      # lost benignly — EACCES: the child already exec'd (its own setpgid won);
      # ESRCH/EPERM: it already exited — so the group is settled either way and
      # the error is swallowed, as dash void-casts the same call.
      # :nocov:
      def setpgid(pid, pgid)
        Process.setpgid(pid, pgid)
      rescue Errno::EACCES, Errno::ESRCH, Errno::EPERM
        nil
      end

      # Fork a child directly into a process group (pgid 0 = the child's own
      # pid, per POSIX, so the kernel does the leader/joiner defaulting): the
      # double setpgid, issued on both sides of the fork, means whichever side
      # runs first settles the group before the child can exec or the parent
      # can wait — the same dance as dash's forkchild/forkparent.
      def fork_grouped(group, &child_main)
        pid = fork { grouped_child(group, &child_main) }
        setpgid(pid, group) if pid
        pid
      end

      def grouped_child(group)
        setpgid(0, group)
        yield
      end
      # :nocov:

      # Job control needs POSIX process groups, which Windows builds lack (the
      # rush-mv8 platform gate); everywhere else Process.setpgid is real.
      def job_control_supported?
        !RbConfig::CONFIG['host_os'].match?(/mswin|mingw|cygwin/)
      end
    end
  end
end
