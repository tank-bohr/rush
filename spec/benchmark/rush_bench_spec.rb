# frozen_string_literal: true

require 'tempfile'

require_relative '../../benchmark/regression_check'
require_relative '../../benchmark/report'

RSpec.describe RushBench do
  let(:benchmark_case) do
    RushBench::Case.new(name: 'tiny', description: 'test workload', iterations: 1, source: ':')
  end
  let(:stats) { RushBench::Stats.new(median_ms: 10.0, min_ms: 9.0, max_ms: 11.0, samples_ms: [9.0, 11.0]) }

  it 'pins the three named workloads and their work counts' do
    expect(described_class::CASES.map { |entry| [entry.name, entry.iterations] }).to eq(
      [['startup', 1], ['while_arithmetic', 10_000], ['expansion_heavy', 2_000]]
    )
  end

  it 'builds a bare rush command and actually removes Bundler injection' do
    rush = described_class.targets.first
    probe = ruby_target('exit(Object.const_defined?(:Bundler) ? 1 : 0)')
    suite = RushBench::Suite.new(cases: [benchmark_case], targets: [probe], timing: timing(samples: 1, warmups: 0))

    expect(rush.command).to include(File.join(described_class::ROOT, 'exe/rush'), '-c')
    expect(rush.environment.values_at('RUBYOPT', 'RUBYLIB', 'BUNDLE_GEMFILE', 'BUNDLE_BIN_PATH')).to eq([nil] * 4)
    expect { suite.run }.not_to raise_error
  end

  it 'executes one correctness smoke, every warmup, and every measured sample' do
    Tempfile.create('rush-benchmark-spec') do |file|
      target = counting_target(file.path)
      result = RushBench::Suite.new(cases: [benchmark_case], targets: [target], timing: timing).run

      expect(File.readlines(file.path).length).to eq(4)
      expect(result.fetch(benchmark_case).fetch(target).samples_ms.length).to eq(2)
    end
  end

  it 'rejects unexpected output from the correctness smoke' do
    target = ruby_target('puts "wrong"; exit 0')
    suite = RushBench::Suite.new(cases: [benchmark_case], targets: [target], timing: timing(samples: 1, warmups: 0))

    expect { suite.run }.to raise_error(RushBench::ExecutionError, /output="wrong\\n"/)
  end

  it 'terminates a benchmark process that exceeds its timeout' do
    target = ruby_target('sleep 10')
    suite = RushBench::Suite.new(cases: [benchmark_case], targets: [target],
                                 timing: timing(samples: 1, warmups: 0, timeout: 0.01))

    expect { suite.run }.to raise_error(RushBench::ExecutionError, /timed out for tiny/)
  end

  it 'rejects a shell process that fails the workload smoke check' do
    target = ruby_target('exit 1')
    suite = RushBench::Suite.new(cases: [benchmark_case], targets: [target], timing: timing(samples: 1, warmups: 0))

    expect { suite.run }.to raise_error(RushBench::ExecutionError, /ruby failed for tiny/)
  end

  it 'emits the stable JSON schema with source and implementation hashes' do
    targets = { RushBench::Target.new(name: 'rush', command: [], environment: {}) => stats,
                RushBench::Target.new(name: 'dash', command: [], environment: {}) => stats }
    report = RushBench::Report.new({ benchmark_case => targets }, samples: 2, warmups: 1).to_h

    expect(report.dig('cases', 'tiny', 'targets', 'rush', 'samples_ms')).to eq([9.0, 11.0])
    expect(report.dig('cases', 'tiny', 'source_sha256')).to match(/\A[0-9a-f]{64}\z/)
    expect(report.fetch('rush_source_sha256')).to match(/\A[0-9a-f]{64}\z/)
    expect(report).to include('schema' => 1, 'samples' => 2, 'warmups' => 1)
  end

  it 'reports only explicitly checked rush regressions beyond the tolerance' do
    baseline = report_hash(100.0)
    current = report_hash(151.0)

    expect(RushBench::RegressionCheck.new(current, baseline, tolerance: 1.5).failures).to eq(
      ['tiny: 151.000ms exceeds 150.000ms']
    )
  end

  it 'rejects incompatible contexts, sampling, schemas, and workloads' do
    baseline = report_hash(100.0)
    current = report_hash(100.0).merge('schema' => 2, 'host' => 'elsewhere', 'samples' => 1)
    current.dig('cases', 'tiny')['source_sha256'] = 'changed'

    expect(RushBench::RegressionCheck.new(current, baseline).failures).to include(
      /unsupported benchmark schema/, 'benchmark context host differs from the baseline',
      'sample count is lower than the baseline', 'tiny: workload definition differs from the baseline'
    )
  end

  def timing(samples: 2, warmups: 1, timeout: 1)
    RushBench::Timing.new(samples: samples, warmups: warmups, timeout: timeout)
  end

  def ruby_target(source)
    RushBench::Target.new(name: 'ruby', command: [Gem.ruby, '-e', source, '--'], environment: {})
  end

  def counting_target(path)
    source = 'File.open(ARGV.fetch(0), "a") { |file| file.puts }'
    RushBench::Target.new(name: 'ruby', command: [Gem.ruby, '-e', source, path, '--'], environment: {})
  end

  def report_hash(median)
    benchmark = { 'description' => 'test workload', 'iterations' => 1, 'source_sha256' => 'same',
                  'targets' => { 'rush' => { 'median_ms' => median } } }
    report_context.merge('schema' => 1, 'samples' => 5, 'warmups' => 1, 'cases' => { 'tiny' => benchmark })
  end

  def report_context
    { 'ruby' => 'ruby', 'platform' => 'platform', 'host' => 'host', 'os' => 'os', 'cpu' => 'cpu',
      'sorbet_runtime_default_checked_level' => 'default' }
  end
end
