# frozen_string_literal: true

# The job-control side of FakeSystemCalls (rush-mv8), mixed in like the real
# SystemCalls' ProcessControl: process grouping, the terminal-ownership model,
# and the reapable-children queue behind waitpid2/wait_stoppable/poll_child.
module FakeJobControl
  # Job-control seams: fork_grouped forks through the (stubbable) fork and
  # records the [pid, pgid] pair a real double setpgid would issue — plus,
  # in tty_leaders, which children were forked carrying the terminal; the
  # platform gate is a knob so specs can exercise the unsupported refusal.
  def fork_grouped(group, tty = nil)
    pid = fork
    return pid unless pid

    @pgids_set << [pid, group]
    @tty_leaders << pid if tty
    pid
  end

  def setpgid(pid, pgid)
    @pgids_set << [pid, pgid]
  end

  def job_control_supported?
    @job_control_supported
  end

  # The terminal-ownership model (rush-mv8.3): open_tty answers an in-memory
  # tty handle whenever the fake session has one (mirroring dash's walk of
  # /dev/tty and fds 2..0); tcsetpgrp records every handover and moves the
  # in-model foreground; tcgetpgrp reads it back — or a queue seeded by
  # provide_tty_foreground, so specs can start the shell in the background
  # (the SIGTTIN wait loop).
  attr_reader :handovers, :tty_leaders

  def open_tty
    return unless tty? || stderr_tty?

    @open_tty ||= StringIO.new
  end

  def tcgetpgrp(_tty)
    return @tty_pgrps.shift unless @tty_pgrps.empty?

    @handovers.last || pgrp
  end

  def tcsetpgrp(_tty, pgid)
    @handovers << pgid
  end

  def provide_tty_foreground(*pgrps)
    @tty_pgrps.concat(pgrps)
  end

  def pgrp
    4242
  end

  # Child-process model for the JobTable: provide_child queues a reapable
  # child (provide_signalled a signal-killed one, provide_stopped a
  # WUNTRACED-visible stop). waitpid2(-1) reaps the next queued one and
  # raises ECHILD when none remain, like the real OS; a specific pid reaps
  # that child if queued, else falls back to the legacy single wait_status
  # knob. Like the real syscall, the plain forms never yield a stopped
  # child — only wait_stoppable and a stoppable poll_child see those.
  # poll_child is the WNOHANG form: nil when the queue is empty rather
  # than blocking.
  def provide_child(pid, exitstatus)
    @children << [pid, FakeSystemCalls::ChildStatus.new(exitstatus, nil)]
  end

  def provide_signalled(pid, signal)
    @children << [pid, FakeSystemCalls::ChildStatus.new(nil, signal)]
  end

  def provide_stopped(pid, signal)
    @children << [pid, FakeSystemCalls::ChildStatus.new(nil, nil, signal)]
  end

  def waitpid2(pid)
    reap(pid, settled_only: true)
  end

  def wait_stoppable(pid)
    reap(pid, settled_only: false)
  end

  def poll_child
    index = @children.index { |_pid, status| !status.stopped? }
    index && @children.delete_at(index)
  end

  def poll_pid(pid)
    child = @children.find { |child_pid, status| child_pid == pid && !status.stopped? }
    child ? @children.delete(child) : [pid, @wait_status]
  end

  def poll_stopped
    @children.shift
  end

  def poll_pid_stopped(pid)
    child = @children.find { |child_pid, _status| child_pid == pid }
    child ? @children.delete(child) : [pid, @wait_status]
  end

  def reap(pid, settled_only:)
    candidates = settled_only ? @children.reject { |_pid, status| status.stopped? } : @children
    return next_child(candidates) if pid == -1

    child = candidates.find { |child_pid, _status| child_pid == pid }
    child ? @children.delete(child) : [pid, @wait_status]
  end

  def next_child(candidates)
    raise Errno::ECHILD if candidates.empty?

    @children.delete(candidates.fetch(0))
  end
end
