# frozen_string_literal: true

RSpec.describe Rush::AST::Pipeline do
  # A real executor (errexit off) so the real #tested / #exit_on_error run; only
  # #run is stubbed to feed canned stage statuses.
  let(:executor) { Rush::Executor.new(system: FakeSystemCalls.new, state: Rush::ShellState.new) }

  it 'runs a single command in-process' do
    allow(executor).to receive(:run).with(:cmd).and_return(Rush::Status.new(5))
    expect(described_class.new([:cmd], false).execute(executor).exitstatus).to eq(5)
  end

  it 'delegates a multi-stage pipeline to PipelineRunner' do
    runner = instance_double(Rush::PipelineRunner, call: Rush::Status.new(7))
    allow(Rush::PipelineRunner).to receive(:new).with(executor, %i[a b]).and_return(runner)
    expect(described_class.new(%i[a b], false).execute(executor).exitstatus).to eq(7)
  end

  it 'inverts a success to failure when negated' do
    allow(executor).to receive(:run).with(:cmd).and_return(Rush::Status.success)
    expect(described_class.new([:cmd], true).execute(executor)).not_to be_success
  end

  it 'inverts a failure to success when negated' do
    allow(executor).to receive(:run).with(:cmd).and_return(Rush::Status.failure)
    expect(described_class.new([:cmd], true).execute(executor)).to be_success
  end
end
