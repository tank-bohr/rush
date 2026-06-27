# frozen_string_literal: true

RSpec.describe Rush::FunctionRunner do
  let(:state) { Rush::ShellState.new }
  let(:executor) { instance_double(Rush::Executor, state: state) }

  before { state.positional = %w[orig] }

  it 'binds the args as positionals, runs the body, and restores them' do
    allow(executor).to receive(:run).with(:body) do
      expect(state.positional).to eq(%w[a b])
      state.last_status = Rush::Status.success
    end
    described_class.new(executor, :body, %w[a b]).call
    expect(state.positional).to eq(%w[orig])
  end

  it 'yields the last body status' do
    allow(executor).to receive(:run).with(:body).and_return(nil)
    state.last_status = Rush::Status.new(2)
    expect(described_class.new(executor, :body, []).call.exitstatus).to eq(2)
  end

  it 'catches return and yields its status' do
    allow(executor).to receive(:run).with(:body).and_raise(Rush::ReturnSignal.new(4))
    expect(described_class.new(executor, :body, []).call.exitstatus).to eq(4)
  end
end
