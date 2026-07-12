#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'stackprof'

require_relative 'cases'
require_relative '../lib/rush/runtime_type_checks'

Rush::RuntimeTypeChecks.configure
require_relative '../lib/rush'

benchmark_case = RushBench::CASES.find { |entry| entry.name == 'while_arithmetic' }
output = ARGV.fetch(0, 'tmp/stackprof-while.dump')
FileUtils.mkdir_p(File.dirname(output))

StackProf.run(mode: :wall, interval: 1_000, out: output) do
  code = Rush::CLI.run(['-c', benchmark_case.source])
  abort "profile workload failed with status #{code}" if code.nonzero?
end

puts "Wrote #{output}"
