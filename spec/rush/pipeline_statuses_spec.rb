# frozen_string_literal: true

RSpec.describe Rush::PipelineStatuses do
  def statuses(*entries)
    described_class.new(entries)
  end

  it 'reports the last stage status' do
    expect(statuses(Rush::Status.new(5), Rush::Status.new(0)).last_stage.exitstatus).to eq(0)
  end

  it 'reports the rightmost failure under pipefail, success when all succeed' do
    expect(statuses(Rush::Status.new(5), Rush::Status.new(7), Rush::Status.new(0)).pipefail.exitstatus).to eq(7)
    expect(statuses(Rush::Status.new(0), Rush::Status.new(0)).pipefail).to be_success
  end

  describe '#verdict / #pipefail_verdict' do
    it 'passes an unstopped verdict through untouched' do
      expect(statuses(Rush::Status.new(5), Rush::Status.new(0)).verdict.stopped?).to be(false)
    end

    it 'rides an earlier stage stop onto the last-stage code (dash: stopped|exit5 answers 5, job Stopped)' do
      verdict = statuses(Rush::Status.stopped(20), Rush::Status.new(5)).verdict
      expect([verdict.exitstatus, verdict.stopsig]).to eq([5, 20])
    end

    it 'keeps an already-stopped verdict as it is (the whole group took the ^Z)' do
      verdict = statuses(Rush::Status.stopped(20), Rush::Status.stopped(20)).verdict
      expect([verdict.exitstatus, verdict.stopsig]).to eq([148, 20])
    end

    it 'carries the stop under pipefail too' do
      verdict = statuses(Rush::Status.stopped(20), Rush::Status.new(5), Rush::Status.new(0)).pipefail_verdict
      expect([verdict.exitstatus, verdict.stopsig]).to eq([5, 20])
    end
  end
end
