# frozen_string_literal: true

require 'English'
require 'etc'
require 'fileutils'

# Runs independent quality tasks in child processes while keeping each task's
# output together. The generated parser is compiled by the parent task before
# any child starts, so no child races to rewrite it.
module QualityGate
  module_function

  TASKS = %w[rubocop reek flay flog steep sorbet spec:parallel].freeze
  LOG_DIR = 'tmp/quality-gate'
  RAKE_COMMAND = [Gem.ruby, Gem.bin_path('rake', 'rake')].freeze
  MAX_SPEC_PROCESSES = 8

  def run
    FileUtils.mkdir_p(LOG_DIR)
    jobs = spawn_jobs
    failures = failed_tasks(jobs.map { |job| finish(job) })
    abort "quality gate failed: #{failures.join(', ')}" unless failures.empty?
  end

  def failed_tasks(results)
    failed = results.reject { |_task, status| status.success? }
    failed.map(&:first)
  end

  def spawn_jobs
    jobs = []
    TASKS.each_with_object(jobs) { |task, launches| launches << launch(task) }
    jobs
  ensure
    jobs.each { |job| finish(job) } if $ERROR_INFO
  end

  def launch(task)
    path = File.join(LOG_DIR, "#{task.tr(':', '-')}.log")
    stream = File.new(path, 'w') # QualityGate owns and closes this child-process log.
    create_job(task, path, stream)
  end

  def create_job(task, path, stream)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    { task: task, path: path, stream: stream, pid: spawn_rake(task, stream), started: started }
  rescue StandardError
    stream.close
    raise
  end

  def spawn_rake(task, stream)
    Process.spawn(*RAKE_COMMAND, task, out: stream, err: %i[child out])
  end

  def finish(job)
    _pid, status = Process.wait2(job.fetch(:pid))
    job.fetch(:stream).close
    report(job, status)
    [job.fetch(:task), status]
  end

  def report(job, status)
    output = File.read(job.fetch(:path))
    puts report_header(job, status)
    print output
    puts unless output.empty? || output.end_with?("\n")
  end

  def report_header(job, status)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - job.fetch(:started)
    "\n== #{job.fetch(:task)}: #{outcome(status)} in #{format('%.1f', elapsed)}s =="
  end

  def outcome(status)
    return 'PASS' if status.success?
    return "FAIL (signal #{status.termsig})" if status.signaled?

    "FAIL (#{status.exitstatus})"
  end

  def integer_env(name, default, valid, message)
    value = Integer(ENV.fetch(name, default.to_s), 10)
    return value if valid.cover?(value)

    raise ArgumentError
  rescue ArgumentError
    abort "#{name} #{message}"
  end

  def spec_processes
    integer_env('RUSH_SPEC_PROCESSES', [Etc.nprocessors, MAX_SPEC_PROCESSES].min,
                1..MAX_SPEC_PROCESSES, "must be an integer from 1 to #{MAX_SPEC_PROCESSES}")
  end

  def spec_seed
    integer_env('RUSH_SPEC_SEED', Random.rand(0..65_535),
                0..65_535, 'must be an integer from 0 to 65535')
  end

  def run_parallel_specs
    processes = spec_processes
    seed = spec_seed
    puts "RSpec: #{processes} processes, seed #{seed}"
    puts "Reproduce with: RUSH_SPEC_PROCESSES=#{processes} RUSH_SPEC_SEED=#{seed} bundle exec rake spec:parallel"
    Rake::FileUtilsExt.sh(Gem.ruby, Gem.bin_path('parallel_tests', 'parallel_rspec'), 'spec',
                          '-n', processes.to_s, '--first-is-1', '--group-by', 'found',
                          '--serialize-stdout', '--combine-stderr',
                          '--verbose-rerun-command', '--test-options', "--seed #{seed}")
  end
end

namespace :coverage do
  desc 'Remove cached SimpleCov results before a complete suite run'
  task :clean do
    rm_rf 'coverage'
  end
end

# A complete suite owns coverage/. Starting from an empty result set prevents a
# prior serial run from masking a missing parallel shard (and vice versa).
task spec: %w[compile coverage:clean]

namespace :spec do
  desc 'Run RSpec in balanced file shards and merge SimpleCov results'
  task parallel: %w[compile coverage:clean] do
    QualityGate.run_parallel_specs
  end
end

namespace :gate do
  desc 'Full gate: compile once, then run independent checks concurrently'
  task parallel: :compile do
    QualityGate.run
  end

  desc 'Full gate in the original deterministic serial order (debug fallback)'
  task serial: %i[compile rubocop reek flay flog steep sorbet spec]
end

default_gate = ENV['RUSH_GATE_SERIAL'] == '1' ? 'gate:serial' : 'gate:parallel'
desc 'Full quality gate (parallel by default; RUSH_GATE_SERIAL=1 for debugging)'
task default: default_gate
