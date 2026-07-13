# frozen_string_literal: true

require_relative 'probe_supervisor'

# Shared helpers for rush-vs-dash differential specs.
module DifferentialHarness
  # Raised when a shell probe does not finish before the harness deadline.
  class ProbeTimeout < StandardError; end

  # Raised when the isolated probe supervisor cannot report a shell status.
  class ProbeFailure < StandardError; end

  # Runs one bounded shell probe through an isolated process-tree supervisor.
  class ProbeRunner
    TIMEOUT = Float(ENV.fetch('RUSH_PROBE_TIMEOUT', '10'))
    raise ArgumentError, 'RUSH_PROBE_TIMEOUT must be finite and positive' unless TIMEOUT.positive? && TIMEOUT.finite?

    POLL_INTERVAL = 0.01

    def self.call(argv, input, env, spawn_options)
      new(argv, input, env, spawn_options).call
    end

    def initialize(argv, input, env, spawn_options)
      @argv = argv
      @input = input
      @env = env
      @spawn_options = spawn_options
      @supervisor = nil
      @threads = nil
    end

    def call
      open_pipes
      launch
      supervise
      result
    ensure
      cleanup
    end

    private

    def open_pipes
      @stdin_read, @stdin_write = IO.pipe
      @stdout_read, @stdout_write = IO.pipe
      @stderr_read, @stderr_write = IO.pipe
      @status_read, @status_write = IO.pipe
      @control_read, @control_write = IO.pipe
    end

    def launch
      @supervisor = ProbeSupervisor.launch(@argv, @env, @spawn_options, supervisor_pipes)
      close_supervisor_ends
      start_io_threads
    end

    def supervisor_pipes
      target = [@stdin_read, @stdout_write, @stderr_write]
      parent = [@stdin_write, @stdout_read, @stderr_read, @status_read, @control_write]
      { target: target, parent: parent, status: @status_write, control: @control_read }
    end

    def close_supervisor_ends
      [@stdin_read, @stdout_write, @stderr_write, @status_write, @control_read].each(&:close)
    end

    def start_io_threads
      @threads = [thread { write_input }, thread { read(@stdout_read) },
                  thread { read(@stderr_read) }, thread { read(@status_read) }]
    end

    def thread(&blk)
      Thread.new(&blk).tap { |value| value.report_on_exception = false }
    end

    def write_input
      @stdin_write.write(@input)
    rescue Errno::EPIPE, IOError
      nil
    ensure
      @stdin_write.close unless @stdin_write.closed?
    end

    def read(stream)
      stream.read
    rescue IOError
      ''
    end

    def supervise
      deadline = monotonic + TIMEOUT
      sleep(POLL_INTERVAL) until finished? || monotonic >= deadline
      raise ProbeTimeout, timeout_message unless finished?
    end

    def finished?
      @threads.none?(&:alive?)
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def timeout_message
      "probe exceeded #{TIMEOUT}s: #{@argv.join(' ')}"
    end

    def result
      [@threads.fetch(1).value, exitstatus]
    end

    def exitstatus
      report = @threads.fetch(3).value
      raise ProbeFailure, 'probe supervisor exited without a status' if report.empty?
      raise ProbeFailure, report.delete_prefix('error:').strip if report.start_with?('error:')

      value = report.delete_prefix('exit:').strip
      value == 'nil' ? nil : Integer(value, 10)
    end

    def cleanup
      request_cleanup
      reap_supervisor
      close_pipes
      @threads&.each(&:join)
    end

    def request_cleanup
      @control_write&.write('.')
    rescue Errno::EPIPE, IOError
      nil
    ensure
      @control_write&.close unless @control_write&.closed?
    end

    def reap_supervisor
      Process.waitpid(@supervisor) if @supervisor
    rescue Errno::ECHILD
      nil
    end

    def close_pipes
      streams = [@stdin_read, @stdin_write, @stdout_read, @stdout_write, @stderr_read,
                 @stderr_write, @status_read, @status_write, @control_read, @control_write]
      streams.compact.each { |stream| stream.close unless stream.closed? }
    end
  end
end
