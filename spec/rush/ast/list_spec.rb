# frozen_string_literal: true

RSpec.describe Rush::AST::List do
  # A real executor (errexit off) runs the real #tested wrapper for async entries.
  let(:executor) { Rush::Executor.new(system: FakeSystemCalls.new, state: Rush::ShellState.new) }

  it 'yields a success status for an empty program' do
    expect(described_class.new([]).execute(executor)).to be_success
  end

  it 'runs each entry in order and returns the last status' do
    entries = %i[a b].map { |ao| Rush::AST::ListEntry.new(and_or: ao, async: false) }
    allow(executor).to receive(:run).and_return(Rush::Status.new(1), Rush::Status.new(2))
    expect(described_class.new(entries).execute(executor).exitstatus).to eq(2)
  end

  it 'runs an async entry in a tested context, returning its status' do
    entry = Rush::AST::ListEntry.new(and_or: :bg, async: true)
    allow(executor).to receive(:run).with(:bg).and_return(Rush::Status.new(3))
    expect(described_class.new([entry]).execute(executor).exitstatus).to eq(3)
  end
end
