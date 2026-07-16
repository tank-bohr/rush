# frozen_string_literal: true

require 'json'

require_relative 'statistics'

module RushBench
  # Report-only same-runner A/B comparison (rush-1eo.5 scaffolding): pools the
  # per-cohort rush medians of two revisions measured interleaved on one
  # machine and prints them side by side with the relative delta. No pass/fail
  # yet — the paired noise-envelope thresholds arrive with the timing-budget
  # rework (rush-1eo.4/.5); until then the numbers are evidence, not a gate.
  class ABReport
    def self.load_side(dir)
      reports = Dir[File.join(dir, '*.json')].map { |path| JSON.parse(File.read(path)) }
      raise ArgumentError, "no benchmark reports in #{dir}" if reports.empty?

      reports
    end

    def self.case_names(reports)
      reports.flat_map { |report| report.fetch('cases').keys }.uniq
    end

    def self.case_medians(reports, name)
      reports.map { |report| report.dig('cases', name, 'targets', 'rush', 'median_ms') }
    end

    def initialize(base, current)
      @base = base
      @current = current
    end

    def print_report(io = $stdout, verdicts: nil)
      io.puts identity_line
      io.puts 'case                        base ms     current ms     delta'
      common_names.each { |name| io.puts row(name, verdicts&.fetch(name, nil)) }
      report_uncomparable(io)
    end

    private

    def identity_line
      "base #{revision(@base)} vs current #{revision(@current)} on #{@current.first.fetch('host')} " \
        "(#{@base.length}+#{@current.length} cohorts); #{@current.first.fetch('ruby')}"
    end

    def revision(side)
      side.first.fetch('revision')
    end

    def row(name, judged)
      base = side_median(@base, name)
      current = side_median(@current, name)
      format('%<name>-20s %<base>14.3f %<current>14.3f %<delta>+8.1f%%%<verdict>s',
             name: name, base: base, current: current, delta: ((current - base) / base) * 100,
             verdict: judged ? "  #{judged.verdict} (floor #{format('%.1f', judged.floor)}ms)" : '')
    end

    # The median of per-cohort medians: each cohort is one warmup-plus-samples
    # run.rb invocation, so cross-cohort drift (thermal, caches, runner load)
    # is damped instead of accumulating into one side.
    def side_median(side, name)
      RushBench.median(ABReport.case_medians(side, name))
    end

    def common_names
      ABReport.case_names(@base) & ABReport.case_names(@current)
    end

    def report_uncomparable(io)
      leftover = (ABReport.case_names(@base) | ABReport.case_names(@current)) - common_names
      io.puts "not comparable (present on one side only): #{leftover.join(', ')}" unless leftover.empty?
    end
  end
end
