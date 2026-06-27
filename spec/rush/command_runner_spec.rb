# frozen_string_literal: true

RSpec.describe Rush::CommandRunner do
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: FakeSystemCalls.new, state: state) }

  def run(words) = described_class.new(executor, Rush::AST::SimpleCommand.new(words)).call

  it 'returns the last status for a command that expands to nothing' do
    state.last_status = Rush::Status.new(5)
    expect(run([]).exitstatus).to eq(5)
  end

  it 'dispatches to a matching builtin' do
    expect(run([Rush::AST::Word.literal('true')])).to be_success
  end

  it 'dispatches to an external program when no builtin matches' do
    external = instance_double(Rush::External, call: Rush::Status.success)
    allow(Rush::External).to receive(:new).and_return(external)
    expect(run([Rush::AST::Word.literal('ls')])).to be_success
    expect(Rush::External).to have_received(:new)
  end
end
