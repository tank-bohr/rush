# frozen_string_literal: true

require 'tempfile'
require 'timeout'

require_relative 'cases'

module RushBench
  # Raised when a benchmarked shell fails or exceeds its workload timeout.
  class ExecutionError < StandardError; end

  # Sampling policy shared by the suite and its report metadata.
  Timing = Data.define(:samples, :warmups, :timeout)

  # Robust aggregate for one target/workload pair; raw samples remain available
  # in JSON so later analysis is not constrained to today's summary statistics.
  Stats = Data.define(:median_ms, :min_ms, :max_ms, :samples_ms)

  # Executes every benchmark in a fresh shell process and measures it with the
  # monotonic clock. Warmups are discarded; reports use the sample median.
  class Suite
    def initialize(cases: CASES, targets: RushBench.targets, timing: Timing.new(samples: 5, warmups: 1, timeout: 30))
      @cases = cases
      @targets = targets
      @timing = timing
    end

    def run
      @cases.to_h { |benchmark_case| [benchmark_case, run_case(benchmark_case)] }
    end

    private

    def run_case(benchmark_case)
      @targets.to_h { |target| [target, measure(target, benchmark_case)] }
    end

    def measure(target, benchmark_case)
      verify(target, benchmark_case)
      @timing.warmups.times { invoke(target, benchmark_case) }
      timings = Array.new(@timing.samples) { elapsed_ms(target, benchmark_case) }
      Stats.new(median_ms: median(timings), min_ms: timings.min, max_ms: timings.max, samples_ms: timings)
    end

    def verify(target, benchmark_case)
      Tempfile.create('rush-benchmark') do |stream|
        status = wait_for(spawn(target, benchmark_case, stream), target, benchmark_case)
        stream.rewind
        assert_verified(status, stream.read, target, benchmark_case)
      end
    end

    def elapsed_ms(target, benchmark_case)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      invoke(target, benchmark_case)
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
    end

    def invoke(target, benchmark_case)
      status = wait_for(spawn(target, benchmark_case, File::NULL), target, benchmark_case)
      assert_success(status, target, benchmark_case)
    end

    def spawn(target, benchmark_case, output)
      return spawn_process(target, benchmark_case, output) unless Object.const_defined?(:Bundler)

      Bundler.with_unbundled_env { spawn_process(target, benchmark_case, output) }
    end

    def spawn_process(target, benchmark_case, output)
      Process.spawn(target.environment, *target.command, benchmark_case.source,
                    out: output, err: %i[child out])
    end

    def wait_for(pid, target, benchmark_case)
      Timeout.timeout(@timing.timeout) { Process.wait2(pid).last }
    rescue Timeout::Error
      terminate(pid)
      raise ExecutionError, "#{target.name} timed out for #{benchmark_case.name} after #{@timing.timeout}s"
    end

    def terminate(pid)
      Process.kill('KILL', pid)
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    def assert_verified(status, output, target, benchmark_case)
      return if status.success? && output.empty?

      raise ExecutionError, failure_message(status, output, target, benchmark_case)
    end

    def assert_success(status, target, benchmark_case)
      return if status.success?

      raise ExecutionError, failure_message(status, '', target, benchmark_case)
    end

    def failure_message(status, output, target, benchmark_case)
      "#{target.name} failed for #{benchmark_case.name}: #{status.inspect}; output=#{output.inspect}"
    end

    def median(values)
      sorted = values.sort
      (sorted[(sorted.length - 1) / 2] + sorted[sorted.length / 2]) / 2.0
    end
  end
end
