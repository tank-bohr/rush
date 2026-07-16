# frozen_string_literal: true

require 'tmpdir'

require_relative '../../../benchmark/ab_judge'
require_relative '../../../benchmark/ab_report'

RSpec.describe RushBench::ABReport do
  it 'prints paired medians-of-cohort-medians with a signed relative delta' do
    report = described_class.new([cohort({ 'startup' => 10.0 }), cohort({ 'startup' => 12.0 })],
                                 [cohort({ 'startup' => 9.0 }), cohort({ 'startup' => 9.5 })])

    expect(output_of(report)).to match(/startup\s+11\.000\s+9\.250\s+-15\.9%/)
  end

  it 'anchors the report to both revisions, the runner, and the cohort counts' do
    report = described_class.new([cohort({ 'startup' => 10.0 }, revision: 'aaa1111')],
                                 [cohort({ 'startup' => 10.0 }, revision: 'bbb2222')])

    expect(output_of(report)).to include('base aaa1111 vs current bbb2222 on runner (1+1 cohorts); ruby 4')
  end

  it 'annotates rows with the verdict and its evidence floor when judged' do
    report = described_class.new([cohort({ 'startup' => 10.0 })], [cohort({ 'startup' => 30.0 })])
    verdicts = { 'startup' => RushBench::ABVerdict.new(verdict: :regression, median_delta: 20.0, floor: 5.0) }

    expect(output_of(report, verdicts: verdicts)).to match(/startup.*\+200\.0%\s+regression \(floor 5\.0ms\)/)
  end

  it 'lists a workload present on one side only instead of comparing it' do
    report = described_class.new([cohort({ 'startup' => 10.0, 'gone' => 5.0 })], [cohort({ 'startup' => 10.0 })])
    text = output_of(report)

    expect(text).to include('not comparable (present on one side only): gone')
    expect(text).not_to match(/^gone.*%$/)
  end

  it 'refuses an empty report directory rather than comparing nothing' do
    Dir.mktmpdir do |dir|
      expect { described_class.load_side(dir) }.to raise_error(ArgumentError, /no benchmark reports/)
    end
  end

  it 'loads every cohort JSON from a side directory in stable order' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'run-1.json'), JSON.generate(cohort({ 'startup' => 10.0 })))
      File.write(File.join(dir, 'run-2.json'), JSON.generate(cohort({ 'startup' => 12.0 })))

      expect(described_class.load_side(dir).length).to eq(2)
    end
  end

  def cohort(medians, revision: 'abc1234')
    cases = medians.to_h do |name, median|
      [name, { 'targets' => { 'rush' => { 'median_ms' => median } } }]
    end
    { 'revision' => revision, 'host' => 'runner', 'ruby' => 'ruby 4', 'cases' => cases }
  end

  def output_of(report, verdicts: nil)
    io = StringIO.new
    report.print_report(io, verdicts: verdicts)
    io.string
  end
end
