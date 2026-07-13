# frozen_string_literal: true

require 'fileutils'
require_relative 'differential_probe'
require 'tempfile'
require 'tmpdir'

# Shared helpers for rush-vs-dash differential specs. Each example compares only
# [stdout, exitstatus]; stderr is intentionally ignored by project policy.
module DifferentialHarness
  def project_root
    File.expand_path('../..', __dir__)
  end

  def rush(source, input = nil)
    rush_with_args(source, [], input)
  end

  def dash(source, input = nil)
    dash_with_args(source, [], input)
  end

  def rush_with_args(source, args, input = nil)
    rush_argv(['-c', source, *args], input)
  end

  def dash_with_args(source, args, input = nil)
    dash_argv(['-c', source, *args], input)
  end

  # Raw invocation forms (no implied -c): option flags, -s/-i, script files.
  # `env` merges extra environment variables into both shells (e.g. ENV, HOME).
  def rush_argv(args, input = nil, env = {})
    run_probe([RbConfig.ruby, '-Ilib', 'exe/rush', *args], input, env, chdir: project_root, pgroup: true)
  end

  def dash_argv(args, input = nil, env = {})
    run_probe(['dash', *args], input, env, pgroup: true)
  end

  # Session-isolated forms for snippets that exit leaving a stopped child
  # behind. The kernel reaps such a stray (orphaned-pgroup SIGHUP+SIGCONT)
  # only if the dying shell's children re-parent OUTSIDE their session.
  # `setsid` makes that true both for a container's pid 1 and for the probe
  # supervisor, preserving the native topology for both shells (rush-erq).
  def rush_in_session(source)
    run_probe(['setsid', RbConfig.ruby, '-Ilib', 'exe/rush', '-c', source], '', {}, chdir: project_root)
  end

  def dash_in_session(source)
    run_probe(['setsid', 'dash', '-c', source], '', {})
  end

  private

  def run_probe(argv, input, env, spawn_options = {})
    ProbeRunner.call(argv, input.to_s, env, spawn_options)
  end
end

RSpec.configure { |config| config.include DifferentialHarness }
