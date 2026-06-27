# frozen_string_literal: true

RSpec.describe Rush::Status do
  it 'wraps exit codes modulo 256' do
    expect(described_class.new(300).exitstatus).to eq(44)
    expect(described_class.new(-1).exitstatus).to eq(255)
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
      process_status = instance_double(Process::Status, exitstatus: 5, termsig: nil)
      expect(described_class.of(process_status).exitstatus).to eq(5)
    end

    it 'maps a terminating signal to 128 + signal' do
      process_status = instance_double(Process::Status, exitstatus: nil, termsig: 9)
      expect(described_class.of(process_status).exitstatus).to eq(137)
    end
  end
end
