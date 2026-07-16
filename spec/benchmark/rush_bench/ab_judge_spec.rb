# frozen_string_literal: true

require_relative '../../../benchmark/ab_judge'

RSpec.describe RushBench::ABJudge do
  it 'confirms a regression when every paired cohort agrees and the floor is cleared' do
    judged = described_class.new([100.0, 101.0, 102.0], [120.0, 121.0, 122.0]).verdict

    expect(judged.verdict).to eq(:regression)
    expect(judged.median_delta).to eq(20.0)
  end

  it 'stays ok on jitter around zero' do
    expect(described_class.new([100.0, 101.0, 102.0], [101.0, 100.0, 102.0]).verdict.verdict).to eq(:ok)
  end

  it 'calls half-floor deltas borderline instead of guessing' do
    expect(described_class.new([100.0, 100.0, 100.0], [103.0, 104.0, 103.0]).verdict.verdict).to eq(:borderline)
  end

  it 'refuses to confirm a regression from cohorts that disagree in sign' do
    judged = described_class.new([100.0, 100.0, 100.0], [98.0, 130.0, 126.0]).verdict

    expect(judged.verdict).to eq(:borderline)
    expect(judged.median_delta).to eq(26.0)
  end

  it 'lets a noisy run raise its own evidence-backed floor' do
    judged = described_class.new([100.0, 120.0, 100.0], [115.0, 135.0, 118.0]).verdict

    expect(judged.floor).to eq(20.0)
    expect(judged.verdict).to eq(:borderline)
  end

  it 'keeps a minimum absolute floor so fast cases cannot flag on microseconds' do
    judged = described_class.new([10.0, 10.0, 10.0], [13.0, 13.0, 13.0]).verdict

    expect(judged.floor).to eq(described_class::MIN_ABS_MS)
    expect(judged.verdict).to eq(:borderline)
  end
end
