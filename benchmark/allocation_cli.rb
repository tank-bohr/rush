# frozen_string_literal: true

require 'optparse'

require_relative 'allocation_check'
require_relative 'allocation_report'
require_relative 'allocation_suite'
require_relative 'env_options'

module RushBench
  # Options for one allocation run: sampling plus the record/check targets.
  AllocationConfiguration = Data.define(:samples, :warmups, :json_path, :baseline_path, :budgets_path)

  # Command-line front end for the allocation report, baseline recording
  # (--json), and the budget ratchet check (--check with --budgets).
  class AllocationCLI
    include EnvOptions

    def self.run(argv, suite: nil)
      new(argv, suite: suite).run
    rescue OptionParser::ParseError, ArgumentError, JSON::ParserError, KeyError, Errno::ENOENT, ExecutionError => e
      warn "allocations: #{e.message}"
      1
    end

    def initialize(argv, suite: nil)
      @argv = argv
      @suite = suite
    end

    def run
      config = configuration
      sampling = AllocationSampling.new(samples: config.samples, warmups: config.warmups)
      report = AllocationReport.new(suite(sampling).run, samples: config.samples, warmups: config.warmups)
      publish(report, config)
    end

    private

    def configuration
      options = { samples: integer_env('RUSH_BENCH_SAMPLES', 5, 1..),
                  warmups: integer_env('RUSH_BENCH_WARMUPS', 1, 0..),
                  json_path: nil, baseline_path: nil, budgets_path: nil }
      parser(options).parse!(@argv)
      validate(AllocationConfiguration.new(**options))
    end

    def parser(options)
      OptionParser.new do |parser|
        parser.on('--json PATH') { |path| options[:json_path] = path }
        parser.on('--check PATH') { |path| options[:baseline_path] = path }
        parser.on('--budgets PATH') { |path| options[:budgets_path] = path }
      end
    end

    def validate(config)
      return config if config.baseline_path.nil? == config.budgets_path.nil?

      raise ArgumentError, '--check and --budgets must be used together'
    end

    def suite(sampling)
      @suite || AllocationSuite.new(runner: rush_runner, sampling: sampling)
    end

    # Loading rush is deferred to the moment a real measurement is needed, so
    # specs can inject a fake suite without booting the shell; the runtime
    # check policy is configured before the first Rush constant loads,
    # exactly as exe/rush does it.
    def rush_runner
      require_relative '../lib/rush/runtime_type_checks'
      Rush::RuntimeTypeChecks.configure
      require_relative '../lib/rush'
      ->(source) { Rush::CLI.run(['-c', source]) }
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
      failures = AllocationCheck.new(current, AllocationCheck.load(config.baseline_path),
                                     AllocationCheck.load(config.budgets_path)).failures
      return puts('Allocation check passed') || 0 if failures.empty?

      warn failures.join("\n")
      1
    end
  end
end
