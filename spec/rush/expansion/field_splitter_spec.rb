# frozen_string_literal: true

RSpec.describe Rush::Expansion::FieldSplitter do
  def split(parts, ifs = nil) = described_class.new(ifs).split(parts)

  it 'keeps a single literal part as one field' do
    expect(split([['abc', false]])).to eq(['abc'])
  end

  it 'splits an unquoted part on whitespace runs, dropping leading/trailing empties' do
    expect(split([['  a  b  ', true]])).to eq(%w[a b])
  end

  it 'does not split quoted or literal parts' do
    expect(split([['a b', false]])).to eq(['a b'])
  end

  it 'joins adjacent parts across a split boundary' do
    expect(split([['x', false], ['1 2', true], ['y', false]])).to eq(%w[x1 2y])
  end

  it 'keeps an empty quoted field but drops an empty unquoted expansion' do
    expect([split([['', false]]), split([['', true]])]).to eq([[''], []])
  end

  it 'disables splitting when IFS is empty' do
    expect(split([['a b', true]], '')).to eq(['a b'])
  end

  it 'splits on a custom IFS character' do
    expect(split([['a:b', true]], ':')).to eq(%w[a b])
  end
end
