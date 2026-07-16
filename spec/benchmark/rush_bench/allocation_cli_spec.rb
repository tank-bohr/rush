# frozen_string_literal: true

require 'tmpdir'

require_relative '../../../benchmark/allocation_cli'

RSpec.describe RushBench::AllocationCLI do
  let(:benchmark_case) do
    RushBench::Case.new(name: 'tiny', description: 'test workload', iterations: 1, source: ':')
  end
  let(:suite) { instance_double(RushBench::AllocationSuite, run: { benchmark_case => [120, 100, 110] }) }

  it 'counts every warmup and sample through a real suite and reports the raw counts' do
    calls = 0
    counting_runner = lambda do |_source|
      calls += 1
      0
    end
    real = RushBench::AllocationSuite.new(runner: counting_runner, cases: [benchmark_case],
                                          sampling: RushBench::AllocationSampling.new(samples: 2, warmups: 1))

    expect(real.run.fetch(benchmark_case).length).to eq(2)
    expect(calls).to eq(3)
  end

  it 'raises when a workload exits nonzero instead of recording a bogus count' do
    real = RushBench::AllocationSuite.new(runner: ->(_source) { 2 },
                                          sampling: RushBench::AllocationSampling.new(samples: 1, warmups: 0),
                                          cases: [benchmark_case])

    expect { real.run }.to raise_error(RushBench::ExecutionError, /tiny failed with status 2/)
  end

  it 'records a versioned baseline JSON with counts, medians, and workload digests' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'baseline.json')
      run_cli(['--json', path])
      report = JSON.parse(File.read(path))

      expect(report).to include('schema' => 1, 'samples' => 5, 'warmups' => 1)
      expect(report.dig('cases', 'tiny')).to include('counts' => [120, 100, 110], 'median' => 110.0)
      expect(report.dig('cases', 'tiny', 'source_sha256')).to match(/\A[0-9a-f]{64}\z/)
    end
  end

  it 'passes the check when the recorded baseline matches and the budget holds' do
    Dir.mktmpdir do |dir|
      baseline, budgets = record_and_budget(dir, 111)

      expect(run_cli(['--check', baseline, '--budgets', budgets], expected: /Allocation check passed/)).to eq(0)
    end
  end

  it 'fails the check with the observed median once the budget is exceeded' do
    Dir.mktmpdir do |dir|
      baseline, budgets = record_and_budget(dir, 109)
      status = nil

      expect { status = quiet_run(['--check', baseline, '--budgets', budgets]) }
        .to output(/tiny: median 110.0 allocated objects exceeds the budget 109/).to_stderr
      expect(status).to eq(1)
    end
  end

  it 'refuses --check without --budgets so the ceilings cannot be skipped' do
    status = nil

    expect { status = described_class.run(['--check', 'x.json'], suite: suite) }
      .to output(/--check and --budgets must be used together/).to_stderr
    expect(status).to eq(1)
  end

  def run_cli(argv, expected: /tiny/)
    status = nil
    expect { status = described_class.run(argv, suite: suite) }.to output(expected).to_stdout
    status
  end

  def quiet_run(argv)
    status = nil
    expect { status = described_class.run(argv, suite: suite) }.to output(/tiny/).to_stdout
    status
  end

  def record_and_budget(dir, ceiling)
    baseline = File.join(dir, 'baseline.json')
    budgets = File.join(dir, 'budgets.json')
    run_cli(['--json', baseline])
    File.write(budgets, JSON.generate({ 'schema' => 1, 'budgets' => { 'tiny' => ceiling } }))
    [baseline, budgets]
  end
end
