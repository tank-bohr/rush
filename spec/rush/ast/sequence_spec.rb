# frozen_string_literal: true

RSpec.describe Rush::AST::Sequence do
  let(:executor) { instance_double(Rush::Executor) }

  it 'yields a success status for an empty program' do
    expect(described_class.new([]).execute(executor)).to be_success
  end

  it 'runs each command in order and returns the last status' do
    allow(executor).to receive(:run).and_return(Rush::Status.new(1), Rush::Status.new(2))
    expect(described_class.new(%i[a b]).execute(executor).exitstatus).to eq(2)
    expect(executor).to have_received(:run).twice
  end
end
