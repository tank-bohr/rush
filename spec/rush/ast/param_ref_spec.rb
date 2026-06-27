# frozen_string_literal: true

RSpec.describe Rush::AST::ParamRef do
  it 'builds a simple reference with no operator' do
    ref = described_class.simple('x')
    expect([ref.name, ref.op, ref.arg]).to eq(['x', nil, nil])
  end

  it 'parses a plain braced name' do
    ref = described_class.parse('name')
    expect([ref.name, ref.op]).to eq(['name', nil])
  end

  it 'parses an operator and its word' do
    ref = described_class.parse('x:-default')
    expect([ref.name, ref.op, ref.arg]).to eq(['x', ':-', 'default'])
  end

  it 'parses a special parameter name' do
    expect(described_class.parse('@').name).to eq('@')
  end
end
