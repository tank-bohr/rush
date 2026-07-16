# frozen_string_literal: true

# Every example is pinned against dash (the escaped-remainder cases fall out
# of dash's ifsbreakup(maxargs) region/cut mechanics, probed on dash 0.5.13).
RSpec.describe Rush::Expansion::ReadFieldScanner do
  def plain(text)
    text.chars.map { |char| [char, false] }
  end

  def esc(text)
    text.chars.map { |char| [char, true] }
  end

  def scan(chars, count, ifs = nil)
    described_class.new(Rush::Expansion::Ifs.new(ifs), count).run(chars)
  end

  it 'splits unescaped text on IFS whitespace, remainder to the last field' do
    expect(scan(plain('x y z w'), 3)).to eq(['x', 'y', 'z w'])
  end

  it 'shields an escaped space from acting as a delimiter' do
    expect(scan(plain('a') + esc(' ') + plain('b c'), 2)).to eq(['a b', 'c'])
  end

  it 'shields an escaped non-whitespace IFS character' do
    expect(scan(plain('a') + esc(':') + plain('b:c'), 2, ':')).to eq(['a:b', 'c'])
  end

  it 'keeps an escaped leading space while stripping unescaped ones' do
    expect(scan(plain(' ') + esc(' ') + plain('a'), 1)).to eq([' a'])
  end

  it 'absorbs one non-whitespace IFS char into a whitespace delimiter run, never two' do
    expect(scan(plain('a : b'), 2, ': ')).to eq(%w[a b])
    expect(scan(plain('a  :  b'), 2, ': ')).to eq(%w[a b])
    expect(scan(plain('a : : b'), 2, ': ')).to eq(['a', ': b'])
    expect(scan(plain('a::b'), 2, ': ')).to eq(['a', ':b'])
  end

  it 'lets an escaped character interrupt whitespace-delimiter absorption' do
    expect(scan(plain('a ') + esc(':') + plain(' b'), 2, ': ')).to eq(['a', ': b'])
  end

  it 'lets a zero-width continuation joint end a whitespace-delimiter run' do
    expect(scan(plain('a ') + [['', true]] + plain(': b'), 2, ': ')).to eq(['a', ': b'])
  end

  it 'keeps escaped trailing whitespace attached to an exact final field' do
    expect(scan(plain('a b') + esc(' '), 2)).to eq(['a', 'b '])
  end

  it 'drops a standalone escaped-whitespace field inside removable trailing text' do
    expect(scan(plain('a b ') + esc(' '), 2)).to eq(%w[a b])
  end

  it 'keeps escaped trailing whitespace glued to remainder content' do
    expect(scan(plain('a b c') + esc(' '), 2)).to eq(['a', 'b c '])
  end

  it 'keeps an escaped space mid-remainder verbatim' do
    expect(scan(plain('a b ') + esc(' ') + plain('c'), 2)).to eq(['a', 'b  c'])
  end

  it 'cuts the delimiter that spends the last variable when nothing follows' do
    expect(scan(plain('a:b:'), 2, ':')).to eq(%w[a b])
  end

  it 'keeps later non-whitespace delimiters in the remainder verbatim' do
    expect(scan(plain('a:b:c:'), 2, ':')).to eq(['a', 'b:c:'])
  end

  it 'treats one non-whitespace IFS char closing a whitespace run as removable' do
    expect(scan(plain('a b  : '), 2, ': ')).to eq(%w[a b])
  end

  it 'clears the trailing cut at a second non-whitespace IFS character' do
    expect(scan(plain('a b :: '), 2, ': ')).to eq(['a', 'b ::'])
  end

  it 'generates empty fields for adjacent non-whitespace delimiters' do
    expect(scan(plain('::x'), 2, ':')).to eq(['', ':x'])
  end

  it 'assigns a lone escaped-whitespace field normally while variables remain' do
    expect(scan(plain('a b ') + esc(' '), 3)).to eq(['a', 'b', ' '])
  end

  it 'yields no fields for whitespace-only input' do
    expect(scan(plain('   '), 2)).to eq([])
  end
end
