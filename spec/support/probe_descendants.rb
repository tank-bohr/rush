# frozen_string_literal: true

# Shared helpers for rush-vs-dash differential specs.
module DifferentialHarness
  # Tracks a probe's descendants across reparenting and process-group changes.
  class ProbeDescendants
    INTERVAL = 0.01

    def self.children(pid)
      Dir.glob("/proc/#{pid}/task/*/children").flat_map do |path|
        File.read(path).split.map { |value| Integer(value, 10) }
      end
    rescue Errno::ENOENT, Errno::ESRCH, Errno::EACCES
      []
    end

    def initialize(root, excluded)
      @root = root
      @excluded = excluded
      @known = {}
      @mutex = Mutex.new
      remember(root)
      @running = true
      @thread = Thread.new { monitor }
      @thread.report_on_exception = false
    end

    def snapshot
      discovered.each { |pid| remember(pid) }
    end

    def group_member?(group)
      known.any? { |pid, started| member?(pid, started, group) }
    end

    def terminate
      stop_monitor
      freeze_known
      kill_known
      reap_known
    end

    private

    def monitor
      while @running
        snapshot
        sleep(INTERVAL)
      end
    end

    def stop_monitor
      @running = false
      @thread.join
    end

    def discovered
      seen = live_known
      queue = (seen.keys + orphaned).uniq
      queue.each { |pid| add(pid, seen) }
      walk(queue, seen)
    end

    def orphaned
      self.class.children(Process.pid) - @excluded - [@root]
    end

    def live_known
      known.select { |pid, started| identity(pid) == started }
    end

    def walk(queue, seen)
      queue.each { |parent| self.class.children(parent).each { |pid| enqueue(pid, queue, seen) } }
      seen.keys
    end

    def enqueue(pid, queue, seen)
      return if seen.key?(pid)

      queue << pid if add(pid, seen)
    end

    def add(pid, seen)
      started = identity(pid)
      seen[pid] = started if started
      started
    end

    def remember(pid)
      started = identity(pid)
      @mutex.synchronize { @known[pid] = started } if started
    end

    def known
      @mutex.synchronize { @known.dup }
    end

    def member?(pid, started, group)
      fields = stat(pid)
      fields && fields.fetch(3) == started && fields.fetch(1) == group
    end

    def identity(pid)
      stat(pid)&.fetch(3)
    end

    def stat(pid)
      fields = File.read("/proc/#{pid}/stat").rpartition(')').last.split
      numbers = fields.values_at(1, 2, 3)
      numbers.map! { |value| Integer(value, 10) }
      numbers.push(fields.fetch(19))
    rescue Errno::ENOENT, Errno::ESRCH, Errno::EACCES, IndexError
      nil
    end

    def freeze_known
      3.times do
        snapshot
        signal_known('STOP')
      end
    end

    def kill_known
      signal_known('KILL')
    end

    def signal_known(signal)
      known.each { |pid, started| signal(signal, pid) if pid != @root && identity(pid) == started }
    end

    def reap_known
      known.each_key { |pid| reap(pid) if pid != @root }
    end

    def signal(signal, pid)
      Process.kill(signal, pid)
    rescue Errno::ESRCH
      nil
    end

    def reap(pid)
      Process.waitpid(pid) if stat(pid)&.fetch(0) == Process.pid
    rescue Errno::ECHILD
      nil
    end
  end
end
