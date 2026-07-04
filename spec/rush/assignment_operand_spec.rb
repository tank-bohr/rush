# frozen_string_literal: true

RSpec.describe Rush::AssignmentOperand do
  let(:env) { Rush::Environment.new({}) }

  it 'exposes the name from a bare operand' do
    parsed = described_class.new('NAME')
    expect(parsed.name).to eq('NAME')
  end

  it 'assigns a value split at the first equals sign' do
    described_class.new('NAME=a=b').assign_to(env)
    expect(env.get('NAME')).to eq('a=b')
  end

  it 'keeps an explicit empty value distinct from a missing assignment' do
    described_class.new('NAME=').assign_to(env)
    expect(env.get('NAME')).to eq('')
  end

  it 'leaves the environment unchanged for a bare name' do
    described_class.new('NAME').assign_to(env)
    expect(env.get('NAME')).to be_nil
  end
end
