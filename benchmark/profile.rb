#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'stackprof'

require_relative 'cases'
require_relative '../lib/rush/runtime_type_checks'

Rush::RuntimeTypeChecks.configure
require_relative '../lib/rush'

case_name = ARGV.fetch(0, 'while_arithmetic')
mode = ARGV.fetch(1, 'wall').to_sym
benchmark_case = RushBench::CASES.find { |entry| entry.name == case_name }
abort "unknown profile workload #{case_name}" unless benchmark_case
abort "unknown StackProf mode #{mode}" unless %i[cpu wall object].include?(mode)

output = ARGV.fetch(2, "tmp/stackprof-#{case_name}-#{mode}.dump")
interval = mode == :object ? 100 : 1_000
FileUtils.mkdir_p(File.dirname(output))

StackProf.run(mode: mode, interval: interval, out: output) do
  code = Rush::CLI.run(['-c', benchmark_case.source])
  abort "profile workload failed with status #{code}" if code.nonzero?
end

puts "Wrote #{output}"
