# frozen_string_literal: true

RSpec.describe Rush::AST::AndOr do
  # A real executor (errexit off) runs the real #tested wrapper; #run is stubbed.
  let(:executor) { Rush::Executor.new(system: FakeSystemCalls.new, state: Rush::ShellState.new) }
  let(:ok) { Rush::Status.success }
  let(:bad) { Rush::Status.failure }

  def and_or(op) = described_class.new(:left, op, :right)

  it 'runs the right side of && only when the left succeeds' do
    allow(executor).to receive(:run).with(:left).and_return(ok)
    allow(executor).to receive(:run).with(:right).and_return(bad)
    expect(and_or(:and).execute(executor)).to eq(bad)
  end

  it 'skips the right side of && when the left fails' do
    allow(executor).to receive(:run).with(:left).and_return(bad)
    expect(and_or(:and).execute(executor)).to eq(bad)
  end

  it 'runs the right side of || only when the left fails' do
    allow(executor).to receive(:run).with(:left).and_return(bad)
    allow(executor).to receive(:run).with(:right).and_return(ok)
    expect(and_or(:or).execute(executor)).to eq(ok)
  end

  it 'skips the right side of || when the left succeeds' do
    allow(executor).to receive(:run).with(:left).and_return(ok)
    expect(and_or(:or).execute(executor)).to eq(ok)
  end
end
