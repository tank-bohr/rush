# frozen_string_literal: true

require 'io/wait'

require_relative 'probe_descendants'
require_relative 'probe_subreaper'

# Shared helpers for rush-vs-dash differential specs.
module DifferentialHarness
  # Owns and reaps one probe tree without changing the RSpec process globally.
  class ProbeSupervisor
    POLL_INTERVAL = 0.01

    def self.launch(argv, env, spawn_options, pipes)
      Process.fork { new(argv, env, spawn_options, pipes).run }
    end

    def initialize(argv, env, spawn_options, pipes)
      @argv = argv
      @env = env
      @spawn_options = spawn_options
      @pipes = pipes
      @target = nil
      @status = nil
      @descendants = nil
      @cancelled = false
      @error = nil
    end

    def run
      setup
      supervise
    rescue StandardError => e
      @error = e
    ensure
      cleanup
      report
      close_pipes
      exit!(@error ? 1 : 0)
    end

    private

    def setup
      @pipes.fetch(:parent).each(&:close)
      close_inherited
      ProbeSubreaper.enable
      @target = Process.spawn(@env, *@argv, **target_options)
      @descendants = ProbeDescendants.new(@target, [])
      @pipes.fetch(:target).each(&:close)
    end

    def target_options
      input, output, error = @pipes.fetch(:target)
      @spawn_options.merge(in: input, out: output, err: error, close_others: true)
    end

    def close_inherited
      keep = [0, 1, 2, *@pipes.values.flatten.filter_map { |stream| stream.fileno unless stream.closed? }]
      Dir.glob('/proc/self/fd/*').each do |path|
        fd = Integer(File.basename(path), 10)
        close_fd(fd) unless keep.include?(fd)
      end
    end

    def close_fd(fd)
      IO.for_fd(fd).close
    rescue Errno::EBADF, ArgumentError
      nil
    end

    def supervise
      until @status || @cancelled
        @cancelled = cleanup_requested?
        reap_nonblock unless @cancelled
        sleep(POLL_INTERVAL) unless @status || @cancelled
      end
    end

    def cleanup_requested?
      return false unless control.wait_readable(0)

      control.read_nonblock(1, exception: false) != :wait_readable
    end

    def control
      @pipes.fetch(:control)
    end

    def reap_nonblock
      _, @status = Process.waitpid2(@target, Process::WNOHANG)
    rescue Errno::ECHILD
      nil
    end

    def cleanup
      @descendants&.snapshot
      terminate_target
      reap_target
      @descendants&.terminate
    end

    def terminate_target
      return unless @target

      group_killed = signal(-@target) if group_owned?
      signal(@target) unless group_killed || @status
    end

    def group_owned?
      !@status || @descendants&.group_member?(@target)
    end

    def signal(target)
      Process.kill('KILL', target)
      true
    rescue Errno::ESRCH
      false
    end

    def reap_target
      _, @status = Process.waitpid2(@target) if @target && !@status
    rescue Errno::ECHILD
      nil
    end

    def report
      status_pipe.write(report_text)
    rescue Errno::EPIPE, IOError
      nil
    end

    def report_text
      return "error:#{@error.class}: #{@error.message}\n" if @error
      return '' if @cancelled

      "exit:#{@status&.exitstatus.inspect}\n"
    end

    def status_pipe
      @pipes.fetch(:status)
    end

    def close_pipes
      (@pipes.values.flatten - @pipes.fetch(:parent)).each { |stream| stream.close unless stream.closed? }
    end
  end
end
