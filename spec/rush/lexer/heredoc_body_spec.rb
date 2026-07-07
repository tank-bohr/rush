# frozen_string_literal: true

RSpec.describe Rush::Lexer::HeredocBody do
  def scan(text)
    described_class.new(text).scan
  end

  def kinds(text)
    scan(text).segments.map { |s| segment_kind(s) }
  end

  it 'keeps plain text as a single literal segment' do
    expect(scan('plain text').literal_text).to eq('plain text')
  end

  it 'parses $name and ${name} into param segments' do
    expect(kinds('a $x b ${y} c')).to eq(%i[literal param literal param literal])
  end

  it 'parses $(...) and `...` into command segments' do
    expect(kinds('$(echo hi) and `date`')).to eq(%i[command literal command])
  end

  it 'parses $((...)) into an arithmetic segment' do
    expect(kinds('sum $((1 + 2)) end')).to eq(%i[literal arith literal])
  end

  it 'keeps an escaped dollar literal rather than a parameter' do
    expect(kinds('\\$x')).to eq([:literal])
    expect(scan('\\$x').literal_text).to eq('$x')
  end

  it 'keeps a backslash before an ordinary character' do
    expect(scan('a\\zb').literal_text).to eq('a\\zb')
  end

  it 'drops a backslash-newline pair as a line continuation' do
    expect(scan("a\\\nb").literal_text).to eq('ab')
  end

  it 'collapses an escaped backslash' do
    expect(scan('a\\\\nb').literal_text).to eq('a\\nb')
  end

  it 'treats a lone $ that starts no name as literal' do
    expect(scan('cost $ 5').literal_text).to eq('cost $ 5')
  end

  it 'raises on an unterminated ${' do
    expect { scan('${x') }.to raise_error(Rush::ParseError, /unterminated/)
  end

  it 'captures substitution and arithmetic bodies verbatim' do
    segments = scan('$(echo hi)`date`$((1 + 2))').segments
    expect(segments.map(&:value)).to eq(['echo hi', 'date', '1 + 2'])
  end

  it 'marks every heredoc segment unquoted' do
    segments = scan('a $x $(c) `d` $((1))').segments
    expect(segments.map(&:quoted)).to all(be(false))
  end

  it 'carries the parameter reference on a param segment' do
    expect(scan('$x').segments.first.value.name).to eq('x')
  end
end
