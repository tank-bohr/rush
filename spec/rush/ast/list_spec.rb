# frozen_string_literal: true

RSpec.describe Rush::AST::List do
  let(:executor) { instance_double(Rush::Executor) }

  it 'yields a success status for an empty program' do
    expect(described_class.new([]).execute(executor)).to be_success
  end

  it 'runs each entry in order and returns the last status' do
    entries = %i[a b].map { |ao| Rush::AST::ListEntry.new(and_or: ao, async: false) }
    allow(executor).to receive(:run).and_return(Rush::Status.new(1), Rush::Status.new(2))
    expect(described_class.new(entries).execute(executor).exitstatus).to eq(2)
  end
end
