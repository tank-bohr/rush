# frozen_string_literal: true

require 'optparse'

require_relative 'env_options'
require_relative 'regression_check'
require_relative 'report'

module RushBench
  Configuration = Data.define(:samples, :warmups, :timeout, :json_path, :baseline_path, :tolerance)

  # Command-line front end for the opt-in benchmark and regression-check tasks.
  class CLI
    include EnvOptions

    def self.run(argv)
      new(argv).run
    rescue OptionParser::ParseError, ArgumentError, JSON::ParserError, KeyError, Errno::ENOENT, ExecutionError => e
      warn "benchmark: #{e.message}"
      1
    end

    def initialize(argv)
      @argv = argv
    end

    def run
      config = configuration
      timing = Timing.new(samples: config.samples, warmups: config.warmups, timeout: config.timeout)
      results = Suite.new(timing: timing).run
      report = Report.new(results, samples: config.samples, warmups: config.warmups, timeout: config.timeout)
      publish(report, config)
    end

    private

    def configuration
      options = { samples: integer_env('RUSH_BENCH_SAMPLES', 5, 1..),
                  warmups: integer_env('RUSH_BENCH_WARMUPS', 1, 0..),
                  timeout: float_env('RUSH_BENCH_TIMEOUT', 30, 0.1), json_path: nil, baseline_path: nil,
                  tolerance: float_env('RUSH_BENCH_TOLERANCE', 1.5, 1.0) }
      parser(options).parse!(@argv)
      Configuration.new(**options)
    end

    def parser(options)
      OptionParser.new do |parser|
        parser.on('--json PATH') { |path| options[:json_path] = path }
        parser.on('--check PATH') { |path| options[:baseline_path] = path }
      end
    end

    def publish(report, config)
      report.print_table
      write_json(config.json_path, report.to_json) if config.json_path
      return 0 unless config.baseline_path

      check(report.to_h, config)
    end

    def write_json(path, json)
      File.write(path, "#{json}\n")
      puts "Wrote #{path}"
    end

    def check(current, config)
      failures = RegressionCheck.new(current, RegressionCheck.load(config.baseline_path),
                                     tolerance: config.tolerance).failures
      return puts("Benchmark check passed (tolerance #{config.tolerance}x)") || 0 if failures.empty?

      warn failures.join("\n")
      1
    end
  end
end
