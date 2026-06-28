# frozen_string_literal: true

RSpec.describe Rush::ForRunner do
  let(:executor) { instance_double(Rush::Executor) }
  let(:env) { Rush::Environment.new({}) }
  let(:state) { Rush::ShellState.new(environment: env) }

  before { allow(executor).to receive(:state).and_return(state) }

  def run(values) = described_class.new(executor, 'x', values, :body).call

  it 'assigns the variable and runs the body for each value' do
    allow(executor).to receive(:run).with(:body).and_return(Rush::Status.success)
    run(%w[a b c])
    expect(env.get('x')).to eq('c')
  end

  it 'returns success for an empty value list' do
    expect(run([])).to be_success
  end

  it 'stops on break, returning the last status' do
    state.record_status(Rush::Status.new(4))
    allow(executor).to receive(:run).with(:body).and_raise(Rush::BreakSignal.new(1))
    expect(run(%w[a b]).exitstatus).to eq(4)
  end

  it 'resumes the next value on continue' do
    state.record_status(Rush::Status.new(5))
    allow(executor).to receive(:run).with(:body).and_raise(Rush::ContinueSignal.new(1))
    expect(run(%w[a b]).exitstatus).to eq(5)
  end

  it 're-raises a multi-level break' do
    allow(executor).to receive(:run).with(:body).and_raise(Rush::BreakSignal.new(2))
    expect { run(%w[a]) }.to raise_error(Rush::BreakSignal) { |e| expect(e.count).to eq(1) }
  end
end
