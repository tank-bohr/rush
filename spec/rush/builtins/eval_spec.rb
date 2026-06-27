# frozen_string_literal: true

RSpec.describe Rush::Builtins::Eval do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args) = described_class.new(executor, ['eval', *args], io).call

  it 'parses and runs the joined arguments in the current shell' do
    expect(run('echo', 'hi')).to be_success
    expect(system.stdout.string).to eq("hi\n")
  end

  it 'returns the status of the evaluated command' do
    expect(run('false')).not_to be_success
  end

  it 'sees and mutates the current environment' do
    run('X=set')
    expect(state.environment.get('X')).to eq('set')
  end

  it 'reports a syntax error with exit status 2' do
    expect(run('if').exitstatus).to eq(2)
    expect(system.stderr.string).to include('eval')
  end

  it 'propagates exit from the evaluated input' do
    expect { run('exit 4') }.to raise_error(Rush::ExitSignal) { |e| expect(e.code).to eq(4) }
  end

  it 'is a no-op success when given no arguments' do
    expect(run).to be_success
  end
end
