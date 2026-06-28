# frozen_string_literal: true

RSpec.describe Rush::Builtins::Shift do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args) = described_class.new(executor, ['shift', *args], io).call

  before { state.positional.replace(%w[a b c]) }

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

  it 'ignores operands past the first' do
    run('2', 'ignored')
    expect(state.positional).to eq(%w[c])
  end

  it 'aborts as a special builtin when the count exceeds the parameter count' do
    expect { run('5') }.to raise_error(Rush::BuiltinError, /can't shift that many/)
    expect(state.positional).to eq(%w[a b c])
  end

  it 'aborts when there are no positionals to shift' do
    state.positional.replace([])
    expect { run }.to raise_error(Rush::BuiltinError, /can't shift that many/)
  end

  it 'aborts on a non-numeric operand' do
    expect { run('abc') }.to raise_error(Rush::BuiltinError, /Illegal number/)
  end

  it 'aborts on a negative operand' do
    expect { run('-1') }.to raise_error(Rush::BuiltinError, /Illegal number/)
  end
end
