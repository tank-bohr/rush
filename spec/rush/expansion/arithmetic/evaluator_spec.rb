# frozen_string_literal: true

RSpec.describe Rush::Expansion::Arithmetic::Evaluator do
  subject(:evaluator) { described_class.new(executor) }

  let(:env) { Rush::Environment.new }
  let(:executor) { Rush::Executor.new(system: FakeSystemCalls.new, state: Rush::ShellState.new(environment: env)) }

  def value(source) = evaluator.evaluate(source)

  it 'respects operator precedence and grouping' do
    expect([value('2+3*4'), value('(2+3)*4')]).to eq([14, 20])
  end

  it 'evaluates every binary operator' do
    results = %w[8/2 8%3 1<<4 64>>2 5&3 5|2 5^1 6-1 2*3].map { |s| value(s) }
    expect(results).to eq([4, 2, 16, 16, 1, 7, 4, 5, 6])
  end

  it 'yields 1 or 0 for comparison and logical operators' do
    results = %w[3<5 5<3 3<=3 4>=9 5>2 3==3 3!=3 2&&7 0||3 0||0].map { |s| value(s) }
    expect(results).to eq([1, 0, 1, 0, 1, 1, 0, 1, 1, 0])
  end

  it 'evaluates the unary operators, stacking them' do
    inputs = ['-5', '+5', '!0', '~0', '- -5', '!!9']
    expect(inputs.map { |s| value(s) }).to eq([-5, 5, 1, -1, 5, 1])
  end

  it 'short-circuits && and || so the dead branch never divides by zero' do
    expect([value('0 && 1/0'), value('1 || 1/0')]).to eq([0, 1])
  end

  it 'evaluates a nested right-associative conditional' do
    expect([value('1?2:3'), value('0?2:3'), value('0 ? 1 : 0 ? 2 : 3')]).to eq([2, 3, 3])
  end

  it 'reads decimal, octal and hexadecimal constants' do
    expect([value('010'), value('0x1F'), value('0XfF')]).to eq([8, 31, 255])
  end

  it 'truncates division and modulo toward zero' do
    expect(%w[-17/5 17/-5 -17/-5 -7%3 7%-3].map { |s| value(s) }).to eq([-3, -3, 3, -1, 1])
  end

  it 'wraps overflow to a signed 64-bit integer' do
    expect(value('9223372036854775807 + 1')).to eq(-9_223_372_036_854_775_808)
  end

  describe 'variable resolution' do
    it 'reads a set name and treats unset or blank as zero' do
      env.assign('x', '5')
      env.assign('blank', '  ')
      expect([value('x*2'), value('unset+1'), value('blank+4')]).to eq([10, 1, 4])
    end

    it 'parses the value as an integer constant, erroring on a non-number' do
      env.assign('x', 'abc')
      expect { value('x+1') }.to raise_error(Rush::ExpansionError)
    end
  end

  describe 'assignment' do
    it 'assigns, returns and persists the value' do
      expect([value('x = 7'), env.get('x')]).to eq([7, '7'])
    end

    it 'evaluates every compound assignment operator in sequence' do
      env.assign('n', '12')
      results = %w[n+=3 n-=1 n*=2 n/=4 n%=5 n<<=2 n>>=1 n&=6 n|=1 n^=3].map { |s| value(s) }
      expect(results).to eq([15, 14, 28, 7, 2, 8, 4, 4, 5, 6])
    end

    it 'is right-associative and evaluates the rhs before reading the target' do
      env.assign('a', '3')
      expect([value('p = q = 4'), value('a += a += 1')]).to eq([4, 8])
    end

    it 'raises when the assignment target is not a name' do
      expect { value('5 = 3') }.to raise_error(Rush::ExpansionError)
    end
  end

  describe 'errors' do
    it 'raises on division by zero' do
      expect { value('1/0') }.to raise_error(Rush::ExpansionError, /division/)
    end

    it 'raises on leftover tokens, an unfinished expression, a bad token and unbalanced parens' do
      ['1 2', '1+', '@', ')', '(1'].each { |s| expect { value(s) }.to raise_error(Rush::ExpansionError) }
    end
  end
end
