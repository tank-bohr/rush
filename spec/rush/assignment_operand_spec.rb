# frozen_string_literal: true

RSpec.describe Rush::AssignmentOperand do
  it 'parses a bare name as an unassigned operand' do
    parsed = described_class.new('NAME')
    expect([parsed.name, parsed.value]).to eq(['NAME', nil])
  end

  it 'parses a value split at the first equals sign' do
    parsed = described_class.new('NAME=a=b')
    expect([parsed.name, parsed.value]).to eq(['NAME', 'a=b'])
  end

  it 'keeps an explicit empty value distinct from a missing assignment' do
    parsed = described_class.new('NAME=')
    expect([parsed.name, parsed.value]).to eq(['NAME', ''])
  end
end
