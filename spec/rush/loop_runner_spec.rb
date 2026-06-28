# frozen_string_literal: true

RSpec.describe Rush::LoopRunner do
  # A real executor (errexit off) runs the real #tested condition wrapper; #run is stubbed.
  let(:executor) { Rush::Executor.new(system: FakeSystemCalls.new, state: state) }
  let(:state) { Rush::ShellState.new }

  def run(sense)
    described_class.new(executor, :cond, :body, sense).call
  end

  def condition(*statuses)
    allow(executor).to receive(:run).with(:cond).and_return(*statuses)
  end

  def body_returns(status)
    allow(executor).to receive(:run).with(:body).and_return(status)
  end

  def body_raises(error)
    allow(executor).to receive(:run).with(:body).and_raise(error)
  end

  it 'runs the body while the condition succeeds' do
    condition(Rush::Status.success, Rush::Status.success, Rush::Status.failure)
    body_returns(Rush::Status.new(2))
    expect(run(:while).exitstatus).to eq(2)
  end

  it 'runs the body until the condition succeeds' do
    condition(Rush::Status.failure, Rush::Status.success)
    body_returns(Rush::Status.new(1))
    expect(run(:until).exitstatus).to eq(1)
  end

  it 'returns success for a loop whose body never runs' do
    condition(Rush::Status.failure)
    expect(run(:while)).to be_success
  end

  it 'exits the loop on break, returning the last status' do
    state.record_status(Rush::Status.new(7))
    condition(Rush::Status.success)
    body_raises(Rush::BreakSignal.new(1))
    expect(run(:while).exitstatus).to eq(7)
  end

  it 're-raises a multi-level break with one fewer level' do
    condition(Rush::Status.success)
    body_raises(Rush::BreakSignal.new(2))
    expect { run(:while) }.to raise_error(Rush::BreakSignal) { |e| expect(e.count).to eq(1) }
  end

  it 'resumes the next iteration on continue' do
    state.record_status(Rush::Status.new(5))
    condition(Rush::Status.success, Rush::Status.failure)
    body_raises(Rush::ContinueSignal.new(1))
    expect(run(:while).exitstatus).to eq(5)
  end

  it 're-raises a multi-level continue with one fewer level' do
    condition(Rush::Status.success)
    body_raises(Rush::ContinueSignal.new(2))
    expect { run(:while) }.to raise_error(Rush::ContinueSignal) { |e| expect(e.count).to eq(1) }
  end
end
