# frozen_string_literal: true

RSpec.describe Rush::Builtins::Set do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new }
  let(:executor) { Rush::Executor.new(system: system, state: state) }
  let(:io) { Rush::IoTable.standard(system) }

  def run(*args)
    described_class.new(executor, ['set', *args], io).call
  end

  it 'replaces the positional parameters with its operands' do
    expect(run('a', 'b', 'c')).to be_success
    expect(state.positional).to eq(%w[a b c])
  end

  it 'ends option processing at a leading --' do
    run('--', '-x', 'y')
    expect(state.positional).to eq(['-x', 'y'])
  end

  it 'clears the parameters with a bare --' do
    state.positional.replace(%w[old])
    run('--')
    expect(state.positional).to be_empty
  end

  it 'leaves the parameters unchanged when given no operands' do
    state.positional.replace(%w[keep])
    expect(run).to be_success
    expect(state.positional).to eq(%w[keep])
  end

  it 'toggles a shell option with - and +' do
    run('-u')
    expect(state.options.on?(:nounset)).to be(true)
    run('+u')
    expect(state.options.on?(:nounset)).to be(false)
  end

  it 'enables and disables errexit with -e and +e' do
    run('-e')
    expect(state.options.on?(:errexit)).to be(true)
    run('+e')
    expect(state.options.on?(:errexit)).to be(false)
  end

  it 'combines option flags with positional parameters after --' do
    run('-ux', '--', 'a', 'b')
    expect([state.options.on?(:nounset), state.options.on?(:xtrace), state.positional]).to eq([true, true, %w[a b]])
  end

  it 'treats a multi-character non-option as a positional and ignores unknown flags' do
    run('foo', 'bar')
    expect(state.positional).to eq(%w[foo bar])
    expect(run('-q')).to be_success
  end

  it 'toggles verbose with -v/+v and the -o verbose long form' do
    run('-v')
    expect(state.options.on?(:verbose)).to be(true)
    run('+v')
    expect(state.options.on?(:verbose)).to be(false)
    run('-o', 'verbose')
    expect(state.options.on?(:verbose)).to be(true)
  end

  it 'toggles an option by long name with -o and +o' do
    run('-o', 'errexit')
    expect(state.options.on?(:errexit)).to be(true)
    run('+o', 'errexit')
    expect(state.options.on?(:errexit)).to be(false)
  end

  it 'ignores an unknown long option name and keeps parsing operands' do
    run('-o', 'bogus', 'x', 'y')
    expect([state.options.on?(:errexit), state.positional]).to eq([false, %w[x y]])
  end
end
