# frozen_string_literal: true

RSpec.describe Rush::Expansion::ReadSplitter do
  def split(line, count, ifs = nil)
    described_class.new(ifs, count).split(line)
  end

  it 'splits a line into the requested number of fields' do
    expect(split('x y z', 3)).to eq(%w[x y z])
  end

  it 'gives the unsplit remainder to the last field, trimming trailing whitespace' do
    expect(split('x y z w extra', 3)).to eq(['x', 'y', 'z w extra'])
  end

  it 'pads with empty strings when there are fewer fields than variables' do
    expect(split('x y', 3)).to eq(['x', 'y', ''])
  end

  it 'strips leading and trailing IFS whitespace for a single variable' do
    expect(split('   hello world   ', 1)).to eq(['hello world'])
  end

  it 'collapses IFS whitespace runs but keeps the remainder verbatim' do
    tab = "\t"
    expect(split("p#{tab}#{tab}q#{tab}r", 2)).to eq(['p', "q#{tab}r"])
  end

  it 'yields empty fields for an empty line' do
    expect(split('', 2)).to eq(['', ''])
  end

  it 'does no splitting when IFS is empty' do
    expect(split('a b', 2, '')).to eq(['a b', ''])
  end

  it 'splits on a custom IFS character' do
    expect(split('a:b:c', 2, ':')).to eq(['a', 'b:c'])
  end

  it 'generates empty fields for adjacent or leading non-whitespace delimiters' do
    expect([split('x::z', 3, ':'), split(':x:', 3, ':')]).to eq([['x', '', 'z'], ['', 'x', '']])
  end

  it 'treats whitespace adjacent to a non-whitespace delimiter as one separator' do
    expect(split('a :  b : c', 3, ' :')).to eq(%w[a b c])
  end
end
