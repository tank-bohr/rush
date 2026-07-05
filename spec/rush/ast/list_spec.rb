# frozen_string_literal: true

RSpec.describe Rush::AST::List do
  # A real executor (errexit off) runs the real #tested wrapper for async entries.
  let(:executor) { Rush::Executor.new(system: FakeSystemCalls.new, state: Rush::ShellState.new) }

  it 'yields a success status for an empty program' do
    list = described_class.new([])
    expect(list).to be_empty
    expect(list.execute(executor)).to be_success
  end

  it 'reports a non-empty program' do
    entry = Rush::AST::ListEntry.new(and_or: :body, async: false)
    expect(described_class.new([entry])).not_to be_empty
  end

  it 'runs each entry in order and returns the last status' do
    entries = %i[a b].map { |ao| Rush::AST::ListEntry.new(and_or: ao, async: false) }
    allow(executor).to receive(:run).with(:a).and_return(Rush::Status.new(1))
    allow(executor).to receive(:run).with(:b).and_return(Rush::Status.new(2))
    allow(executor).to receive(:tested).and_call_original

    expect(described_class.new(entries).execute(executor).exitstatus).to eq(2)
    expect(executor).to have_received(:run).with(:a).once
    expect(executor).to have_received(:run).with(:b).once
    expect(executor).not_to have_received(:tested)
  end

  it 'launches an async entry in a tested context, returning its launch status' do
    entry = Rush::AST::ListEntry.new(and_or: :bg, async: true)
    allow(executor).to receive(:run_async).with(:bg).and_return(Rush::Status.success)
    allow(executor).to receive(:tested).and_call_original

    expect(described_class.new([entry]).execute(executor)).to be_success
    expect(executor).to have_received(:tested).once
    expect(executor).to have_received(:run_async).with(:bg).once
  end
end
