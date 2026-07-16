#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'optparse'

require_relative 'ab_judge'
require_relative 'ab_report'
require_relative 'cases'

module RushBench
  # Orchestrates the same-runner A/B comparison: interleaved benchmark/run.rb
  # cohorts for the merge-base worktree and the current checkout, alternating
  # which side goes first so drift lands on both sides, then ABJudge verdicts
  # with one extra cohort when a case lands borderline. Exits 1 only on a
  # confirmed regression — the workflow is opt-in evidence, not a required
  # check (rush-1eo.5).
  class ABRun
    def self.run(argv)
      new(parse(argv)).run
    rescue ArgumentError, JSON::ParserError, KeyError, Errno::ENOENT => e
      warn "ab-run: #{e.message}"
      1
    end

    def self.parse(argv)
      options = { cohorts: 3 }
      flags(options).parse!(argv)
      options
    end

    def self.flags(options)
      OptionParser.new do |parser|
        parser.on('--base DIR') { |dir| options[:base] = dir }
        parser.on('--out DIR') { |dir| options[:out] = dir }
        parser.on('--cohorts N', Integer) { |n| options[:cohorts] = n }
      end
    end

    def initialize(options)
      @base_dir = options.fetch(:base) { raise ArgumentError, '--base DIR (the merge-base worktree) is required' }
      @out_dir = options.fetch(:out) { raise ArgumentError, '--out DIR is required' }
      @cohorts = options.fetch(:cohorts)
    end

    def run
      (1..@cohorts).each { |index| run_cohort(index) }
      publish(retry_borderline(judge))
    end

    private

    def run_cohort(index)
      order = index.odd? ? %i[base current] : %i[current base]
      order.each { |side| run_side(side, index) }
    end

    def run_side(side, index)
      dir = side == :base ? @base_dir : ROOT
      out = File.join(side_dir(side), format('run-%02d.json', index))
      env = { 'BUNDLE_GEMFILE' => File.join(dir, 'Gemfile'), 'BUNDLE_PATH' => bundle_path }
      system(env, 'bundle', 'exec', 'ruby', 'benchmark/run.rb', '--json', out,
             chdir: dir, out: File::NULL, exception: true)
    end

    def side_dir(side)
      path = File.join(File.expand_path(@out_dir), side.to_s)
      FileUtils.mkdir_p(path)
      path
    end

    # An explicit BUNDLE_PATH survives into the worktree side, which has no
    # .bundle/config of its own; with an unchanged lockfile both sides then
    # resolve the identical gem set.
    def bundle_path
      ENV.fetch('BUNDLE_PATH') do
        vendored = File.join(ROOT, 'vendor/bundle')
        Dir.exist?(vendored) ? vendored : nil
      end
    end

    def judge
      base = ABReport.load_side(side_dir(:base))
      current = ABReport.load_side(side_dir(:current))
      names = ABReport.case_names(base) & ABReport.case_names(current)
      names.to_h { |name| [name, judged_case(base, current, name)] }
    end

    def judged_case(base, current, name)
      ABJudge.new(ABReport.case_medians(base, name), ABReport.case_medians(current, name)).verdict
    end

    def retry_borderline(verdicts)
      states = verdicts.values.map(&:verdict)
      return verdicts unless states.include?(:borderline) && !states.include?(:regression)

      puts 'borderline case detected — running one extra cohort'
      run_cohort(@cohorts + 1)
      judge
    end

    def publish(verdicts)
      report = ABReport.new(ABReport.load_side(side_dir(:base)), ABReport.load_side(side_dir(:current)))
      report.print_report(verdicts: verdicts)
      write_report(report, verdicts)
      verdicts.values.map(&:verdict).include?(:regression) ? 1 : 0
    end

    def write_report(report, verdicts)
      File.open(File.join(File.expand_path(@out_dir), 'report.txt'), 'w') do |file|
        report.print_report(file, verdicts: verdicts)
      end
    end
  end
end

exit RushBench::ABRun.run(ARGV) if __FILE__ == $PROGRAM_NAME
