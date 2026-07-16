# frozen_string_literal: true

RSpec.describe Rush::JobTable::InterruptibleWait do
  let(:control) { Rush::JobTable::Control.new }
  let(:reaped) { [7, :reaped_status] }

  def wait(system, pending: -> {})
    described_class.new(system, control, 7, pending).call
  end

  it 'returns the pending interruption as a Status before ever polling' do
    system = instance_double(Rush::SystemCalls)

    result = wait(system, pending: -> { 130 })

    expect(result).to be_a(Rush::Status)
    expect(result.exitstatus).to eq(130)
  end

  it 'polls WNOHANG until the target reports, then hands back its raw status' do
    system = instance_double(Rush::SystemCalls)
    allow(system).to receive(:poll_pid).with(7).and_return(nil, nil, reaped)

    expect(wait(system)).to eq(:reaped_status)
    expect(system).to have_received(:poll_pid).exactly(3).times
  end

  it 'polls WUNTRACED instead when stops are visible to this shell' do
    control.engage(nil)
    system = instance_double(Rush::SystemCalls)
    allow(system).to receive(:poll_pid_stopped).with(7).and_return(reaped)

    expect(wait(system)).to eq(:reaped_status)
  end
end
