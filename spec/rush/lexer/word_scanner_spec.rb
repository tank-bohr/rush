# frozen_string_literal: true

RSpec.describe Rush::Lexer::WordScanner do
  def scan(source)
    scanner = StringScanner.new(source)
    [described_class.new(scanner).scan, scanner]
  end

  def field(source) = scan(source).first.segments.map(&:value).join

  it 'reads a bare literal word' do
    expect(field('echo')).to eq('echo')
  end

  it 'removes single quotes and keeps their contents verbatim' do
    expect(field("'a;b'")).to eq('a;b')
  end

  it 'removes double quotes' do
    expect(field('"a b"')).to eq('a b')
  end

  it 'unescapes a backslash-escaped space, keeping the word intact' do
    expect(field('a\\ b')).to eq('a b')
  end

  it 'treats a trailing backslash and a line continuation as empty' do
    expect(field('end\\')).to eq('end')
    expect(field("a\\\nb")).to eq('ab')
  end

  it 'honours backslash escapes inside double quotes' do
    expect(field('"a\\"b"')).to eq('a"b')
    expect(field('"a\\zb"')).to eq('a\\zb')
  end

  it 'stops at an unquoted operator and leaves the rest unscanned' do
    word, scanner = scan('foo;bar')
    expect([word.segments.map(&:value).join, scanner.rest]).to eq(['foo', ';bar'])
  end

  it 'marks quoted segments as quoted and bare runs as unquoted' do
    expect(scan("a'q'").first.segments.map(&:quoted)).to eq([false, true])
  end

  it 'raises on an unterminated single quote' do
    expect { scan("'oops") }.to raise_error(Rush::ParseError, /single quote/)
  end

  it 'raises on an unterminated double quote' do
    expect { scan('"oops') }.to raise_error(Rush::ParseError, /double quote/)
  end
end
