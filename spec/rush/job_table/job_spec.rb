# frozen_string_literal: true

RSpec.describe Rush::JobTable::Job do
  subject(:job) { described_class.new(1, 50, members: [50, 51]) }

  it 'starts running, with the leader pid and every member listed' do
    expect([job.number, job.pid, job.members, job.running?]).to eq([1, 50, [50, 51], true])
  end

  it 'defaults members to the single pid' do
    expect(described_class.new(1, 50).members).to eq([50])
  end

  it 'routes a stop to the parked state: alive, re-waitable, not finished' do
    job.finish(FakeSystemCalls::ChildStatus.new(nil, nil, 20))
    expect([job.running?, job.stopped?, job.finished?]).to eq([false, true, false])
  end

  it 'answers 128+stopsig while stopped, immediately and repeatably (dash-probed wait %1)' do
    job.stop(20)
    expect([job.harvest { raise ArgumentError, 'must not wait' }.exitstatus, job.status.exitstatus]).to eq([148, 148])
  end

  it 'settles for good on a final status, Done beating the earlier stop' do
    job.stop(20)
    job.finish(FakeSystemCalls::ChildStatus.new(nil, 9))
    expect([job.stopped?, job.finished?, job.status.exitstatus]).to eq([false, true, 137])
  end

  it 'harvests a running job through the supplied wait, which may itself park it' do
    status = job.harvest { FakeSystemCalls::ChildStatus.new(nil, nil, 19) }
    expect([status.exitstatus, job.stopped?]).to eq([147, true])
  end

  it 'remembers a final harvest without re-waiting (dash never frees on wait)' do
    job.harvest { FakeSystemCalls::ChildStatus.new(4, nil) }
    expect(job.harvest { raise ArgumentError, 'must not wait' }.exitstatus).to eq(4)
  end
end
