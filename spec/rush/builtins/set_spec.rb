# frozen_string_literal: true

RSpec.describe Rush::Builtins::Set do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args) = described_class.new(executor, ['set', *args], io).call

  it 'replaces the positional parameters with its operands' do
    expect(run('a', 'b', 'c')).to be_success
    expect(state.positional).to eq(%w[a b c])
  end

  it 'ends option processing at a leading --' do
    run('--', '-x', 'y')
    expect(state.positional).to eq(['-x', 'y'])
  end

  it 'clears the parameters with a bare --' do
    state.positional = %w[old]
    run('--')
    expect(state.positional).to be_empty
  end

  it 'leaves the parameters unchanged when given no operands' do
    state.positional = %w[keep]
    expect(run).to be_success
    expect(state.positional).to eq(%w[keep])
  end
end
