# frozen_string_literal: true

RSpec.describe Rush::Builtins::PrintfFormatter do
  def render(template, *args) = described_class.new(args).render(template)
  def text(template, *) = render(template, *).first

  it 'substitutes %s and processes format escapes' do
    expect(text("%s\n", 'hi')).to eq("hi\n")
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
    expect(text('%%')).to eq('%')
  end

  it 'treats a missing argument as empty or zero' do
    expect(text('[%s][%d]')).to eq('[][0]')
  end

  it 'reports a present non-numeric argument and uses zero' do
    result, ok = render('%d', 'abc')
    expect([result, ok]).to eq(['0', false])
  end

  it 'keeps a lone percent that is not a conversion' do
    expect(text('100%')).to eq('100%')
  end
end
