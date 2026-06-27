# frozen_string_literal: true

RSpec.describe Rush::AST::If do
  # A real executor (errexit off) runs the real #tested condition wrapper; #run is stubbed.
  let(:executor) { Rush::Executor.new(system: FakeSystemCalls.new, state: Rush::ShellState.new) }

  it 'runs the consequent when the condition succeeds' do
    allow(executor).to receive(:run).with(:cond).and_return(Rush::Status.success)
    allow(executor).to receive(:run).with(:then).and_return(Rush::Status.new(3))
    expect(described_class.new(:cond, :then, :else).execute(executor).exitstatus).to eq(3)
  end

  it 'runs the alternative when the condition fails' do
    allow(executor).to receive(:run).with(:cond).and_return(Rush::Status.failure)
    allow(executor).to receive(:run).with(:else).and_return(Rush::Status.new(4))
    expect(described_class.new(:cond, :then, :else).execute(executor).exitstatus).to eq(4)
  end

  it 'yields success when the condition fails and there is no alternative' do
    allow(executor).to receive(:run).with(:cond).and_return(Rush::Status.failure)
    expect(described_class.new(:cond, :then, nil).execute(executor)).to be_success
  end
end
