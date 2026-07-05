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

  it 'leaves the parameters unchanged when given only short options' do
    state.positional.replace(%w[keep])
    expect(run('-u')).to be_success
    expect(state.options.on?(:nounset)).to be(true)
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

  it 'recognizes a non-identical -- as the option terminator' do
    state.positional.replace(%w[old])
    run(+'--')
    expect(state.positional).to be_empty
  end

  it 'keeps parsing options after a short option before operands' do
    run('-v', '+v', 'arg')
    expect([state.options.on?(:verbose), state.positional]).to eq([false, %w[arg]])
  end

  it 'treats a bare - as a positional operand' do
    expect(run('-', 'x')).to be_success
    expect(state.positional).to eq(['-', 'x'])
  end

  it 'treats a multi-character non-option as a positional and ignores unknown flags' do
    run('foo', 'bar')
    expect(state.positional).to eq(%w[foo bar])
    expect(run('-q')).to be_success
  end

  it 'does not record unknown flags as enabled options' do
    run('-q')
    enabled = state.options.instance_variable_get(:@enabled)
    expect(enabled).not_to include(nil)
  end

  it 'toggles verbose with -v/+v and the -o verbose long form' do
    run('-v')
    expect(state.options.on?(:verbose)).to be(true)
    run('+v')
    expect(state.options.on?(:verbose)).to be(false)
    run('-o', 'verbose')
    expect(state.options.on?(:verbose)).to be(true)
  end

  it 'toggles allexport with -a/+a and exports subsequent assignments' do
    run('-a')
    expect(state.options.on?(:allexport)).to be(true)
    state.variables.assign('X', '1')
    run('+a')
    state.variables.assign('Y', '2')
    expect([state.options.on?(:allexport), state.variables.exported.slice('X', 'Y')]).to eq([false, { 'X' => '1' }])
  end

  it 'toggles allexport with the long option name' do
    run('-o', 'allexport')
    state.variables.assign('X', '1')
    run('+o', 'allexport')
    state.variables.assign('Y', '2')
    expect(state.variables.exported.slice('X', 'Y')).to eq('X' => '1')
  end

  it 'accepts string subclasses as option flags' do
    flag = Class.new(String).new('-u')
    run(flag)
    expect(state.options.on?(:nounset)).to be(true)
  end

  it 'toggles an option by long name with -o and +o' do
    run('-o', 'errexit')
    expect(state.options.on?(:errexit)).to be(true)
    run('+o', 'errexit')
    expect(state.options.on?(:errexit)).to be(false)
  end

  it 'uses the long option name after -o at the current parser position' do
    run('-v', '-o', 'errexit', 'arg')
    expect([state.options.on?(:verbose), state.options.on?(:errexit), state.positional]).to eq([true, true, %w[arg]])
  end

  it 'handles -o without a following name as a consumed no-op' do
    state.positional.replace(%w[old])
    expect(run('-o')).to be_success
    expect(state.positional).to be_empty
  end

  it 'ignores an unknown long option name and keeps parsing operands' do
    run('-o', 'bogus', 'x', 'y')
    expect([state.options.on?(:errexit), state.positional]).to eq([false, %w[x y]])
  end
end
