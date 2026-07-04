# frozen_string_literal: true

RSpec.describe Rush::Assignments do
  let(:variables) { Rush::ShellVariables.new(Rush::Environment.new('x' => 'global')) }
  let(:assignments) { described_class.new(variables) }

  it 'returns a bare name without assigning it' do
    expect(assignments.apply('NAME')).to eq('NAME')
    expect(variables.get('NAME')).to be_nil
  end

  it 'assigns a value split at the first equals sign' do
    expect(assignments.apply('NAME=a=b')).to eq('NAME')
    expect(variables.get('NAME')).to eq('a=b')
  end

  it 'keeps an explicit empty value distinct from a missing assignment' do
    assignments.apply('NAME=')
    expect(variables.get('NAME')).to eq('')
  end

  it 'runs the hook after parsing and before assignment' do
    seen = nil
    assignments.apply('x=local') { |name| seen = [name, variables.get(name)] }
    expect([seen, variables.get('x')]).to eq([%w[x global], 'local'])
  end
end
