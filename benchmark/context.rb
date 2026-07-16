# frozen_string_literal: true

require 'digest'
require 'etc'
require 'open3'
require 'socket'
require 'time'

require_relative 'cases'

module RushBench
  # Environment fingerprint shared by the timing and allocation reports: the
  # keys a regression check may compare for comparability, plus provenance
  # fields (host, revision, timestamp) that anchor a committed baseline to
  # attributable evidence.
  module Context
    module_function

    def snapshot
      { 'generated_at' => Time.now.utc.iso8601, 'revision' => revision,
        'ruby' => RUBY_DESCRIPTION, 'platform' => RUBY_PLATFORM, 'host' => Socket.gethostname,
        'os' => os, 'cpu' => cpu, 'rush_source_sha256' => rush_source_digest,
        'rush_runtime_typechecks' => runtime_typechecks,
        'sorbet_runtime_default_checked_level_env' => ENV.fetch('SORBET_RUNTIME_DEFAULT_CHECKED_LEVEL', 'unset') }
    end

    def runtime_typechecks
      ENV.fetch('RUSH_RUNTIME_TYPECHECKS', nil) == '1' ? 'enabled' : 'disabled'
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
      output, status = Open3.capture2('git', 'rev-parse', '--short', 'HEAD', chdir: ROOT)
      return 'unknown' unless status.success?

      revision = output.strip
      dirty_worktree? ? "#{revision}-dirty" : revision
    end

    def dirty_worktree?
      output, = Open3.capture2('git', 'status', '--porcelain', chdir: ROOT)
      !output.empty?
    end

    def rush_source_digest
      digest = Digest::SHA256.new
      source_paths.each { |path| digest << path.delete_prefix(ROOT) << "\0" << File.binread(path) }
      digest.hexdigest
    end

    def source_paths
      Dir[File.join(ROOT, '{lib/**/*.rb,exe/*}')]
    end
  end
end
