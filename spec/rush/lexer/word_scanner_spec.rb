# frozen_string_literal: true

RSpec.describe Rush::Lexer::WordScanner do
  def scan(source)
    scanner = StringScanner.new(source)
    [described_class.next_word(scanner), scanner]
  end

  def field(source)
    scan(source).first.segments.map(&:value).join
  end

  it 'reads a bare literal word' do
    expect(field('echo')).to eq('echo')
  end

  it 'removes single quotes and keeps their contents verbatim' do
    expect(field("'a;b'")).to eq('a;b')
  end

  it 'removes double quotes' do
    expect(field('"a b"')).to eq('a b')
  end

  it 'keeps empty double quotes as one empty quoted segment' do
    segments = scan('""').first.segments
    expect(segments.map { |s| [s.value, s.quoted] }).to eq([['', true]])
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

  it 'produces a :param segment for $name' do
    segment = scan('$foo').first.segments.first
    expect([segment_kind(segment), segment.value.name]).to eq([:param, 'foo'])
  end

  it 'recognizes special and single-digit positional parameters' do
    names = ['$?', '$1'].map { |src| scan(src).first.segments.first.value.name }
    expect(names).to eq(%w[? 1])
  end

  it 'parses a braced parameter with an operator' do
    ref = scan('${x:-d}').first.segments.first.value
    expect([ref.name, ref.op, ref.arg]).to eq(['x', ':-', 'd'])
  end

  it 'keeps a parameter inside double quotes, marked quoted' do
    segment = scan('"$x"').first.segments.first
    expect([segment_kind(segment), segment.quoted]).to eq([:param, true])
  end

  it 'treats a lone $ as a literal, quoted or not' do
    expect([field('$ '), field('"$ "')]).to eq(['$', '$ '])
  end

  it 'scans the whole operator word including blanks in whole mode' do
    word = described_class.entire('a b c')
    expect(word.segments.map(&:value).join).to eq('a b c')
  end

  it 'raises on an unterminated braced parameter' do
    expect { scan('${x') }.to raise_error(Rush::ParseError, /unterminated/)
  end

  it 'produces a :command segment for $(...)' do
    segment = scan('$(echo hi)').first.segments.first
    expect([segment_kind(segment), segment.value]).to eq([:command, 'echo hi'])
  end

  it 'produces an :arith segment for $((...)), keeping balanced inner parens' do
    segment = scan('$(( (1+2) * 3 ))').first.segments.first
    expect([segment_kind(segment), segment.value]).to eq([:arith, ' (1+2) * 3 '])
  end

  it 'treats $( ( as command substitution, not arithmetic' do
    segment = scan('$( (echo hi) )').first.segments.first
    expect([segment_kind(segment), segment.value]).to eq([:command, ' (echo hi) '])
  end

  it 'produces a :command segment for a backtick substitution' do
    segment = scan('`date`').first.segments.first
    expect([segment_kind(segment), segment.value]).to eq([:command, 'date'])
  end

  it 'keeps a command substitution inside double quotes, marked quoted' do
    segment = scan('"$(echo hi)"').first.segments.first
    expect([segment_kind(segment), segment.quoted]).to eq([:command, true])
  end

  it 'keeps a backtick substitution inside double quotes, marked quoted' do
    segment = scan('"`date`"').first.segments.first
    expect([segment_kind(segment), segment.value, segment.quoted]).to eq([:command, 'date', true])
  end
end
