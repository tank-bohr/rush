# frozen_string_literal: true

require 'digest'
require 'etc'
require 'json'
require 'open3'
require 'socket'
require 'time'

require_relative 'suite'

module RushBench
  # Converts a Suite result to a stable, machine-readable schema and a compact
  # table suitable for benchmark notes and before/after comparisons.
  class Report
    SCHEMA = 1

    def initialize(results, samples:, warmups:, timeout: 30)
      @results = results
      @samples = samples
      @warmups = warmups
      @timeout = timeout
    end

    def to_h
      metadata.merge('cases' => cases_hash)
    end

    def to_json(*)
      JSON.pretty_generate(to_h)
    end

    def print_table(io = $stdout)
      io.puts metadata_line
      io.puts 'case                      rush ms      dash ms    rush/dash'
      @results.each { |benchmark_case, targets| io.puts row(benchmark_case, targets) }
    end

    private

    def metadata
      { 'schema' => SCHEMA, 'generated_at' => Time.now.utc.iso8601, 'revision' => revision,
        'ruby' => RUBY_DESCRIPTION, 'platform' => RUBY_PLATFORM, 'host' => Socket.gethostname,
        'os' => os, 'cpu' => cpu, 'rush_source_sha256' => rush_source_digest,
        'samples' => @samples, 'warmups' => @warmups, 'timeout' => @timeout,
        'sorbet_runtime_default_checked_level' => ENV.fetch('SORBET_RUNTIME_DEFAULT_CHECKED_LEVEL', 'default') }
    end

    def cases_hash
      @results.to_h { |benchmark_case, targets| [benchmark_case.name, case_hash(benchmark_case, targets)] }
    end

    def case_hash(benchmark_case, targets)
      { 'description' => benchmark_case.description, 'iterations' => benchmark_case.iterations,
        'source_sha256' => Digest::SHA256.hexdigest(benchmark_case.source),
        'targets' => targets.to_h { |target, stats| [target.name, stats_hash(stats)] } }
    end

    def stats_hash(stats)
      { 'median_ms' => rounded(stats.median_ms), 'min_ms' => rounded(stats.min_ms),
        'max_ms' => rounded(stats.max_ms), 'samples_ms' => stats.samples_ms.map { |sample| rounded(sample) } }
    end

    def row(benchmark_case, targets)
      rush = stats_for(targets, 'rush').median_ms
      dash = stats_for(targets, 'dash').median_ms
      format('%<name>-20s %<rush>12.3f %<dash>12.3f %<ratio>12.1fx',
             name: benchmark_case.name, rush: rush, dash: dash, ratio: rush / dash)
    end

    def stats_for(targets, name)
      targets.find { |target, _stats| target.name == name }.last
    end

    def metadata_line
      "Ruby #{RUBY_VERSION} on #{RUBY_PLATFORM}; #{@samples} samples after #{@warmups} warmup(s); " \
        "Sorbet=#{ENV.fetch('SORBET_RUNTIME_DEFAULT_CHECKED_LEVEL', 'default')}"
    end

    def rush_source_digest
      digest = Digest::SHA256.new
      source_paths.each { |path| digest << path.delete_prefix(RushBench::ROOT) << "\0" << File.binread(path) }
      digest.hexdigest
    end

    def source_paths
      Dir[File.join(RushBench::ROOT, '{lib/**/*.rb,exe/*}')]
    end

    def os
      Etc.uname.values_at(:sysname, :release, :machine).join(' ')
    end

    def cpu
      line = File.foreach('/proc/cpuinfo').find { |entry| entry.start_with?('model name') }
      line ? line.split(':', 2).last.strip : RbConfig::CONFIG.fetch('host_cpu')
    rescue Errno::ENOENT
      RbConfig::CONFIG.fetch('host_cpu')
    end

    def revision
      output, status = Open3.capture2('git', 'rev-parse', '--short', 'HEAD', chdir: RushBench::ROOT)
      return 'unknown' unless status.success?

      revision = output.strip
      dirty_worktree? ? "#{revision}-dirty" : revision
    end

    def dirty_worktree?
      output, = Open3.capture2('git', 'status', '--porcelain', chdir: RushBench::ROOT)
      !output.empty?
    end

    def rounded(value)
      value.round(6)
    end
  end
end
