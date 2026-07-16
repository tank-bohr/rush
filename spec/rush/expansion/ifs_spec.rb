# frozen_string_literal: true

RSpec.describe Rush::Expansion::Ifs do
  it 'defaults unset IFS to the standard whitespace with no other delimiters' do
    ifs = described_class.new(nil)

    expect(ifs.whitespace).to eq([' ', "\t", "\n"])
    expect(ifs.others).to eq([])
    expect(ifs.null?).to be(false)
  end

  it 'treats null IFS as no delimiters at all' do
    ifs = described_class.new('')

    expect([ifs.whitespace, ifs.others]).to eq([[], []])
    expect(ifs.null?).to be(true)
  end

  it 'partitions a mixed IFS into whitespace and other delimiters, deduplicated' do
    ifs = described_class.new(":: \t")

    expect(ifs.whitespace).to eq([' ', "\t"])
    expect(ifs.others).to eq([':'])
  end

  it 'classifies characters only within the configured set' do
    ifs = described_class.new(': ')

    expect([ifs.whitespace?(' '), ifs.whitespace?("\t"), ifs.whitespace?(':')]).to eq([true, false, false])
    expect([ifs.other?(':'), ifs.other?(' '), ifs.other?('-')]).to eq([true, false, false])
  end

  it 'preserves an empty splat only when the leading IFS character is a non-whitespace' do
    expect(described_class.new(': ').preserve_empty_splat?).to be(true)
    expect(described_class.new(' :').preserve_empty_splat?).to be(false)
    expect(described_class.new(nil).preserve_empty_splat?).to be(false)
  end
end
