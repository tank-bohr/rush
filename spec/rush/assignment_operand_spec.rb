# frozen_string_literal: true

RSpec.describe Rush::AssignmentOperand do
  it 'parses a bare name as an unassigned operand' do
    parsed = described_class.parse('NAME')
    expect([parsed.name, parsed.value]).to eq(['NAME', nil])
  end

  it 'parses a name and value around the first equals sign' do
    parsed = described_class.parse('NAME=a=b')
    expect([parsed.name, parsed.value]).to eq(['NAME', 'a=b'])
  end

  it 'keeps an explicit empty value distinct from a missing assignment' do
    parsed = described_class.parse('NAME=')
    expect([parsed.name, parsed.value]).to eq(['NAME', ''])
  end

  it 'assigns present values to the environment' do
    env = Rush::Environment.new({})
    described_class.parse('NAME=value').assign_to(env)
    expect(env.get('NAME')).to eq('value')
  end

  it 'leaves the environment unchanged for a bare name' do
    env = Rush::Environment.new({})
    described_class.parse('NAME').assign_to(env)
    expect(env.get('NAME')).to be_nil
  end
end
