# frozen_string_literal: true

RSpec.describe Rush::Builtins::PrintfFormatter do
  def render(template, *args)
    described_class.new(args).render(template)
  end

  def text(template, *)
    render(template, *).first
  end

  it 'substitutes %s and processes format escapes' do
    expect(render("%s\n", 'hi')).to eq(["hi\n", true])
    expect(text('a\tb')).to eq("a\tb")
  end

  it 'keeps an unknown escape and a trailing backslash literally' do
    expect(text('x\zy')).to eq('x\zy')
    expect(text('end\\')).to eq('end\\')
  end

  it 'cycles the template until the arguments are exhausted' do
    expect(text('%s %s\n', 'a', 'b', 'c', 'd')).to eq("a b\nc d\n")
    expect(text('%s\n', 'a', 'b', 'c')).to eq("a\nb\nc\n")
  end

  it 'uses the template once when it has no conversions, ignoring extra args' do
    expect(text('hi\n', 'x', 'y')).to eq("hi\n")
  end

  it 'honours flags, width and precision via numeric and string conversions' do
    expect(text('[%5s]', 'hi')).to eq('[   hi]')
    expect(text('[%-5s]', 'hi')).to eq('[hi   ]')
    expect(text('%03d', '7')).to eq('007')
  end

  it 'formats the integer conversions, mapping %i and %u to decimal' do
    expect(text('%d %x %X %o %i %u', '255', '255', '255', '8', '5', '9')).to eq('255 ff FF 10 5 9')
  end

  it 'prints the first character for %c and a literal percent' do
    expect(text('%c%c', 'abc', 'xyz')).to eq('ax')
    expect(text('[%3c]', 'abc')).to eq('[  a]')
    expect(text('%%')).to eq('%')
  end

  it 'treats a missing argument as empty or zero without reporting a numeric error' do
    expect(render('[%s][%d]')).to eq(['[][0]', true])
  end

  it 'accepts signed, leading-blank, octal and hexadecimal integer spellings' do
    expect(render('%d %i %d %d %d', '+7', '-7', '  -7', '010', '0x10')).to eq(['7 -7 -7 8 16', true])
  end

  it 'keeps an accumulated numeric prefix while reporting incomplete conversion' do
    expect(render('%d %d %d %d', '12x', '+12x', '-010x', '0x10z')).to eq(['12 12 -8 16', false])
    expect(render('%d %d', '12 ', '08')).to eq(['12 0', false])
    expect(render('%d', '0b10')).to eq(['0', false])
  end

  it 'formats POSIX quoted characters and rejects a quote without a character' do
    expect(render('%d %d', "'A", '"+')).to eq(['65 43', true])
    expect(render('%d', "'")).to eq(['0', false])
  end

  it 'formats negative unsigned integers at uintmax width' do
    expect(render('%u %x %o', '-1', '-2', '-2'))
      .to eq(['18446744073709551615 fffffffffffffffe 1777777777777777777776', true])
    expect(render('%u', '-18446744073709551615')).to eq(['1', true])
  end

  it 'clamps each signed overflow while reporting failure' do
    expect(render('%d', '9223372036854775808')).to eq(['9223372036854775807', false])
    expect(render('%d', '-9223372036854775809')).to eq(['-9223372036854775808', false])
  end

  it 'accepts uintmax and separately reports positive and negative unsigned overflow' do
    expect(render('%u', '0')).to eq(['0', true])
    expect(render('%u', '18446744073709551615')).to eq(['18446744073709551615', true])
    expect(render('%u', '18446744073709551616')).to eq(['18446744073709551615', false])
    expect(render('%u', '-18446744073709551616')).to eq(['18446744073709551615', false])
  end

  it 'counts one diagnostic per bad operand even when it is both incomplete and out of range' do
    formatter = described_class.new(%w[18446744073709551616x 7 oops])
    expect(formatter.render('%u %u %u')).to eq(['18446744073709551615 7 0', false])
    expect(formatter.errors).to eq(2)
  end

  it 'reports a present non-numeric argument and uses zero' do
    result, ok = render('%d', 'abc')
    expect([result, ok]).to eq(['0', false])
  end

  it 'keeps valid recycled passes successful and a later recycled failure sticky' do
    expect(render('%d\n', '1', '2')).to eq(["1\n2\n", true])
    expect(render('%d\n', '1', 'abc')).to eq(["1\n0\n", false])
  end

  it 'keeps a lone percent that is not a conversion' do
    expect(text('100%')).to eq('100%')
  end
end
