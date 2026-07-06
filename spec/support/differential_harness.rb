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
    out, _err, status = Open3.capture3(RbConfig.ruby, '-Ilib', 'exe/rush', '-c', source, *args,
                                       chdir: project_root, stdin_data: input.to_s, close_others: true)
    [out, status.exitstatus]
  end

  def dash_with_args(source, args, input = nil)
    out, _err, status = Open3.capture3('dash', '-c', source, *args,
                                       stdin_data: input.to_s, close_others: true)
    [out, status.exitstatus]
  end
end

RSpec.configure { |config| config.include DifferentialHarness }
