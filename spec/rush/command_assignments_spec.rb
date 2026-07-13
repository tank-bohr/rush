# frozen_string_literal: true

RSpec.describe Rush::CommandAssignments do
  let(:system) { FakeSystemCalls.new }
  let(:state) { Rush::ShellState.new(environment: Rush::Environment.new({})) }
  let(:executor) { Rush::Executor.new(system: system, state: state) }

  def word(text)
    Rush::AST::Word.literal(text)
  end

  def assignment(name, text)
    Rush::AST::Assignment.new(name: name, value: word(text))
  end

  def assignments(*pairs)
    described_class.new(pairs.map { |name, text| assignment(name, text) }, executor.expander)
  end

  it 'reports the assignment names in source order' do
    expect(assignments(%w[A 1], %w[B 2], %w[A 3]).names).to eq(%w[A B A])
  end

  it 'persists expanded assignment values to shell variables' do
    assignments(%w[A 1]).persist_to(state.variables)
    expect(state.variables.get('A')).to eq('1')
  end

  it 'enables assignment-context tilde expansion' do
    state.variables.assign('HOME', '/home/test')
    assignments(['A', 'prefix:~/file']).persist_to(state.variables)
    expect(state.variables.get('A')).to eq('prefix:/home/test/file')
  end

  it 'builds an external environment from exported variables plus assignment overlays' do
    state.variables.assign('BASE', 'old')
    state.variables.export('BASE')

    env = assignments(%w[A 1], %w[BASE new]).environment_for(state.variables)

    expect(env).to eq('BASE' => 'new', 'A' => '1')
    expect(state.variables.get('A')).to be_nil
    expect(state.variables.get('BASE')).to eq('old')
  end

  it 'selects and persists only the prefix-assignment environment' do
    values = assignments(%w[A 1], %w[B 2])
    environment = { 'BASE' => 'kept', 'A' => 'one', 'B' => 'two' }

    expect(values.temporary_environment(environment)).to eq('A' => 'one', 'B' => 'two')
    values.persist_environment(environment, state.variables)
    expect([state.variables.get('BASE'), state.variables.get('A'), state.variables.get('B')])
      .to eq([nil, 'one', 'two'])
  end

  it 'rejects an overlay containing a readonly name' do
    state.variables.readonly('LOCKED')
    values = assignments(%w[OPEN yes], %w[LOCKED no])

    expect { values.validate(state.variables) }.to raise_error(Rush::ReadonlyError, 'LOCKED: is read only')
    expect(state.variables.get('OPEN')).to be_nil
  end
end
