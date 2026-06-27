# frozen_string_literal: true

RSpec.describe Rush::Builtins::Shift do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args) = described_class.new(executor, ['shift', *args], io).call

  before { state.positional = %w[a b c] }

  it 'discards the first parameter by default' do
    expect(run).to be_success
    expect(state.positional).to eq(%w[b c])
  end

  it 'discards n parameters when given a count' do
    run('2')
    expect(state.positional).to eq(%w[c])
  end

  it 'leaves the parameters unchanged for a zero count' do
    run('0')
    expect(state.positional).to eq(%w[a b c])
  end

  it 'fails without modifying when the count exceeds the parameter count' do
    expect(run('5')).not_to be_success
    expect(state.positional).to eq(%w[a b c])
    expect(system.stderr.string).to include('shift')
  end
end
