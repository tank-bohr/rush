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

  it 'persists expanded assignment values to shell variables' do
    assignments(%w[A 1]).persist_to(state.variables)
    expect(state.variables.get('A')).to eq('1')
  end

  it 'builds an external environment from exported variables plus assignment overlays' do
    state.variables.assign('BASE', 'old')
    state.variables.export('BASE')

    env = assignments(%w[A 1], %w[BASE new]).environment_for(state.variables)

    expect(env).to eq('BASE' => 'new', 'A' => '1')
    expect(state.variables.get('A')).to be_nil
    expect(state.variables.get('BASE')).to eq('old')
  end
end
