# frozen_string_literal: true

RSpec.describe Rush::Builtins::TestTokens do
  def kinds(*args)
    tokens = described_class.new(args)
    (0...args.size).map { |index| tokens.kind_at(index) }
  end

  it 'classifies operators by table kind and unknown words as operands' do
    expect(kinds('!', '-a', '-o', '(', ')', '-n', 'word', 'x', '=', '-eq'))
      .to eq(%i[bunop band bor lparen rparen unop operand operand binop binop])
  end

  it 'returns :eoi past the end of the arguments' do
    expect(described_class.new(['x']).kind_at(1)).to eq(:eoi)
  end

  it 'demotes a unary primary in final position to an operand' do
    expect(kinds('-n')).to eq([:operand])
    expect(kinds('!', '-t')).to eq(%i[bunop operand])
  end

  it 'demotes a unary primary followed by a binary primary to an operand' do
    expect(kinds('-t', '=', '-t')).to eq(%i[operand binop operand])
    expect(kinds('-e', '-a', '-e')).to eq(%i[unop band operand])
  end

  it 'demotes a ( that closes the argument list to an operand' do
    expect(kinds('(')).to eq([:operand])
    expect(kinds('(', 'x')).to eq(%i[lparen operand])
  end
end
