# frozen_string_literal: true

RSpec.describe Rush::Expansion::Arithmetic::Number do
  subject(:number) { Object.new.extend(described_class) }

  def calculate(method, *args)
    number.send(method, *args)
  end

  it 'parses integer constants and reports invalid numbers' do
    expect([calculate(:parse, ' 42 '), calculate(:parse, '-010'), calculate(:parse, '+0x10')]).to eq([42, -8, 16])
    expect { calculate(:parse, 'nope') }.to raise_error(Rush::ExpansionError, 'arithmetic: invalid number "nope"')
  end

  it 'wraps values to signed 64-bit integers' do
    limit = 1 << 63
    expect([calculate(:wrap, limit - 1), calculate(:wrap, limit), calculate(:wrap, -limit - 1)])
      .to eq([limit - 1, -limit, limit - 1])
  end

  it 'maps booleans to arithmetic truth values' do
    expect([calculate(:bool, true), calculate(:bool, false)]).to eq([1, 0])
  end

  it 'evaluates unary operators with wrapping' do
    limit = 1 << 63
    expect(['+', '-', '!', '~'].map { |op| calculate(:unary, op, 0) }).to eq([0, 0, 1, -1])
    expect(calculate(:unary, '-', -limit)).to eq(-limit)
  end

  it 'evaluates binary arithmetic, bitwise and comparison operators' do
    expressions = {
      '+' => [7, 5, 12], '-' => [7, 5, 2], '*' => [7, 5, 35],
      '/' => [-17, 5, -3], '%' => [-17, 5, -2],
      '<<' => [1, 65, 2], '>>' => [-8, 65, -4],
      '&' => [6, 3, 2], '|' => [4, 1, 5], '^' => [7, 3, 4],
      '<' => [2, 3, 1], '<=' => [3, 3, 1], '>' => [2, 3, 0], '>=' => [2, 3, 0],
      '==' => [3, 3, 1], '!=' => [3, 3, 0]
    }
    expect(expressions.map { |op, (left, right, _expected)| [op, calculate(:binary, op, left, right)] })
      .to eq(expressions.map { |op, (_left, _right, expected)| [op, expected] })
    expect(calculate(:binary, '+', (1 << 63) - 1, 1)).to eq(-(1 << 63))
  end

  it 'divides with POSIX truncation toward zero and reports zero divisors' do
    pairs = [[17, 5, 3], [-17, 5, -3], [17, -5, -3], [-17, -5, 3]]
    expect(pairs.map { |left, right, _expected| calculate(:divide, left, right) })
      .to eq(pairs.map(&:last))
    expect { calculate(:divide, 1, 0) }.to raise_error(Rush::ExpansionError, 'arithmetic: division by zero')
  end

  it 'computes modulo using the truncated quotient sign convention' do
    pairs = [[17, 5, 2], [-17, 5, -2], [17, -5, 2], [-17, -5, -2]]
    expect(pairs.map { |left, right, _expected| calculate(:modulo, left, right) })
      .to eq(pairs.map(&:last))
  end
end
