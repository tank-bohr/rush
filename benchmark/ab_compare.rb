#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'ab_report'

module RushBench
  # Entry point: ab_compare.rb BASE_REPORT_DIR CURRENT_REPORT_DIR — each
  # directory holds the --json outputs of the interleaved benchmark/run.rb
  # cohorts for one revision (see .github/workflows/benchmark.yml).
  module ABCompare
    def self.run(argv)
      base, current = argv.values_at(0, 1)
      abort 'usage: ab_compare.rb BASE_REPORT_DIR CURRENT_REPORT_DIR' unless base && current

      compare(base, current)
    end

    def self.compare(base, current)
      ABReport.new(ABReport.load_side(base), ABReport.load_side(current)).print_report
      0
    rescue ArgumentError, JSON::ParserError, KeyError, Errno::ENOENT => e
      warn "ab-compare: #{e.message}"
      1
    end
  end
end

exit RushBench::ABCompare.run(ARGV) if __FILE__ == $PROGRAM_NAME
