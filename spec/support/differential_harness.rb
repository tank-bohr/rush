# frozen_string_literal: true

require 'fileutils'
require 'open3'
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
    out, _err, status = Open3.capture3(env, RbConfig.ruby, '-Ilib', 'exe/rush', *args,
                                       chdir: project_root, stdin_data: input.to_s, close_others: true)
    [out, status.exitstatus]
  end

  def dash_argv(args, input = nil, env = {})
    out, _err, status = Open3.capture3(env, 'dash', *args, stdin_data: input.to_s, close_others: true)
    [out, status.exitstatus]
  end

  # Session-isolated forms for snippets that exit leaving a stopped child
  # behind. The kernel reaps such a stray (orphaned-pgroup SIGHUP+SIGCONT)
  # only if the dying shell's children re-parent OUTSIDE their session;
  # inside a container they land on a same-session pid 1, the group never
  # orphans, and the stopped child holds the capture pipes open past any
  # Timeout (rush-erq). setsid restores the native topology for both shells.
  def rush_in_session(source)
    out, _err, status = Open3.capture3('setsid', RbConfig.ruby, '-Ilib', 'exe/rush', '-c', source,
                                       chdir: project_root, stdin_data: '', close_others: true)
    [out, status.exitstatus]
  end

  def dash_in_session(source)
    out, _err, status = Open3.capture3('setsid', 'dash', '-c', source, stdin_data: '', close_others: true)
    [out, status.exitstatus]
  end
end

RSpec.configure { |config| config.include DifferentialHarness }
