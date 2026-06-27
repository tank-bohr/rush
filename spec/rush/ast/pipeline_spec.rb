# frozen_string_literal: true

RSpec.describe Rush::AST::Pipeline do
  let(:executor) { instance_double(Rush::Executor) }

  it 'runs a single command in-process' do
    allow(executor).to receive(:run).with(:cmd).and_return(Rush::Status.new(5))
    expect(described_class.new([:cmd]).execute(executor).exitstatus).to eq(5)
  end

  it 'delegates a multi-stage pipeline to PipelineRunner' do
    runner = instance_double(Rush::PipelineRunner, call: Rush::Status.new(7))
    allow(Rush::PipelineRunner).to receive(:new).with(executor, %i[a b]).and_return(runner)
    expect(described_class.new(%i[a b]).execute(executor).exitstatus).to eq(7)
  end
end
