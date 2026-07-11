# frozen_string_literal: true

RSpec.describe Rush::Lexer::QuotedWord do
  def word(text)
    described_class.new(text).word
  end

  it 'keeps single quotes as ordinary characters' do
    expect(word("'x'").literal_text).to eq("'x'")
  end

  it 'removes embedded double quotes and keeps their content' do
    expect(word('pre"a b"post').literal_text).to eq('prea bpost')
  end

  it 'unescapes a backslash-escaped } and the double-quote specials' do
    expect(word('\\}\\"\\$\\`\\\\').literal_text).to eq('}"$`\\')
  end

  it 'keeps the backslash before an ordinary character' do
    expect(word('\\x').literal_text).to eq('\\x')
  end

  it 'keeps a trailing backslash literal' do
    expect(word('a\\').literal_text).to eq('a\\')
  end

  it 'drops a line continuation' do
    expect(word("a\\\nb").literal_text).to eq('ab')
  end

  it 'reads a parameter reference as a quoted segment' do
    segment = word('$x').segments.first
    expect([segment.value.name, segment.quoted]).to eq(['x', true])
  end

  it 'keeps a lone $ that begins no reference literal' do
    expect(word('cost $ 5').literal_text).to eq('cost $ 5')
  end

  it 'reads command substitutions and backticks as quoted segments' do
    segments = word('$(echo hi)`date`').segments
    expect(segments.map(&:value)).to eq(['echo hi', 'date'])
    expect(segments.map(&:quoted)).to all(be(true))
  end
end
