# frozen_string_literal: true

require_relative '../../../benchmark/allocation_check'

RSpec.describe RushBench::AllocationCheck do
  it 'passes a current report that matches the baseline and sits under budget' do
    expect(described_class.new(report_hash(100.0), report_hash(90.0), budgets_hash(101)).failures).to eq([])
  end

  it 'reports a budget breach with the observed median and the ceiling' do
    expect(described_class.new(report_hash(102.5), report_hash(90.0), budgets_hash(101)).failures).to eq(
      ['tiny: median 102.5 allocated objects exceeds the budget 101']
    )
  end

  it 'never compares the current median against the recorded baseline median' do
    regressed_far_beyond_baseline = report_hash(1000.0)

    expect(described_class.new(regressed_far_beyond_baseline, report_hash(10.0), budgets_hash(1001)).failures)
      .to eq([])
  end

  it 'rejects incompatible schemas, contexts, sampling, and workload drift' do
    current = report_hash(100.0).merge('ruby' => 'other ruby', 'samples' => 1, 'warmups' => 0)
    current.dig('cases', 'tiny')['source_sha256'] = 'changed'

    expect(described_class.new(current, report_hash(100.0), budgets_hash(101).merge('schema' => 2)).failures)
      .to include(/unsupported allocation schema/, 'allocation context ruby differs from the baseline',
                  'sample count is lower than the baseline', 'warmup count is lower than the baseline',
                  'tiny: workload definition differs from the baseline')
  end

  it 'ignores host, os, and cpu differences so CI can check a developer-recorded baseline' do
    current = report_hash(100.0).merge('host' => 'ci-runner', 'os' => 'other os', 'cpu' => 'other cpu')

    expect(described_class.new(current, report_hash(100.0), budgets_hash(101)).failures).to eq([])
  end

  it 'rejects budgets that do not cover exactly the baseline case set' do
    stray = { 'schema' => 1, 'budgets' => { 'tiny' => 101, 'stray' => 5 } }

    expect(described_class.new(report_hash(100.0), report_hash(100.0), stray).failures).to eq(
      ['allocation budgets do not cover exactly the baseline case set']
    )
  end

  it 'rejects a renamed workload before budgets are consulted' do
    current = report_hash(100.0)
    current['cases'] = { 'renamed' => current['cases'].fetch('tiny') }

    expect(described_class.new(current, report_hash(100.0), budgets_hash(101)).failures).to include(
      'allocation case names differ from the baseline'
    )
  end

  def report_hash(median)
    tiny = { 'description' => 'test workload', 'iterations' => 1, 'source_sha256' => 'same',
             'counts' => [median], 'median' => median }
    context_hash.merge('schema' => 1, 'samples' => 5, 'warmups' => 1, 'cases' => { 'tiny' => tiny })
  end

  def context_hash
    { 'ruby' => 'ruby', 'platform' => 'platform', 'host' => 'host', 'os' => 'os', 'cpu' => 'cpu',
      'rush_runtime_typechecks' => 'disabled', 'sorbet_runtime_default_checked_level_env' => 'unset' }
  end

  def budgets_hash(ceiling)
    { 'schema' => 1, 'budgets' => { 'tiny' => ceiling } }
  end
end
