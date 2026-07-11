# frozen_string_literal: true

RSpec.describe Rush::Status do
  it 'keeps the raw exit status (the wrap to 0-255 happens at the process boundary)' do
    expect(described_class.new(300).exitstatus).to eq(300)
    expect(described_class.new(7).exitstatus).to eq(7)
  end

  it 'reports success only for a zero status' do
    expect(described_class.success).to be_success
    expect(described_class.failure).not_to be_success
  end

  it 'builds a failure with a custom code' do
    expect(described_class.failure(7).exitstatus).to eq(7)
  end

  describe '.of' do
    it 'uses the process exit status when the child exited normally' do
      process_status = instance_double(Process::Status, exitstatus: 5, termsig: nil, stopped?: false)
      expect(described_class.of(process_status).exitstatus).to eq(5)
    end

    it 'maps a terminating signal to 128 + signal, keeping the signal for the jobs listing' do
      process_status = instance_double(Process::Status, exitstatus: nil, termsig: 9, stopped?: false)
      status = described_class.of(process_status)
      expect([status.exitstatus, status.termsig, status.stopsig]).to eq([137, 9, nil])
    end

    it 'keeps no termsig on a plain exit' do
      process_status = instance_double(Process::Status, exitstatus: 5, termsig: nil, stopped?: false)
      status = described_class.of(process_status)
      expect([status.termsig, status.stopped?]).to eq([nil, false])
    end

    it 'maps a WUNTRACED stop to 128 + stopsig, keeping the signal (rush-mv8.4)' do
      process_status = instance_double(Process::Status, exitstatus: nil, termsig: nil, stopped?: true, stopsig: 20)
      status = described_class.of(process_status)
      expect([status.exitstatus, status.stopsig, status.stopped?]).to eq([148, 20, true])
    end
  end

  describe '#with_stop' do
    it 'returns itself without a stop signal to carry' do
      status = described_class.new(5)
      expect(status.with_stop(nil)).to be(status)
    end

    it 'returns itself when already stopped' do
      status = described_class.stopped(20)
      expect(status.with_stop(19)).to be(status)
    end

    it 'rides a sibling stop signal onto the exit code' do
      carried = described_class.new(5).with_stop(20)
      expect([carried.exitstatus, carried.stopsig, carried.stopped?]).to eq([5, 20, true])
    end
  end

  describe '.stopped' do
    it 'builds a stopped status; plain statuses are never stopped' do
      expect(described_class.stopped(19).exitstatus).to eq(147)
      expect(described_class.stopped(19).stopped?).to be(true)
      expect(described_class.new(148).stopped?).to be(false)
    end
  end
end
