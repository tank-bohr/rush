# frozen_string_literal: true

RSpec.describe Rush::Lexer::WordScanner do
  def scan(source, interactive: false)
    scanner = StringScanner.new(source)
    [described_class.next_word(scanner, interactive: interactive), scanner]
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

  it 'keeps a backslash that ends the input literal, and joins a continuation' do
    expect(field('end\\')).to eq('end\\')
    expect(field("a\\\nb")).to eq('ab')
  end

  it 'asks for more input when a continuation ends an interactive buffer' do
    expect { scan("a\\\n", interactive: true) }.to raise_error(Rush::IncompleteInput, /continuation/)
  end

  it 'joins a mid-buffer continuation without asking for more input' do
    word, = scan("a\\\nb c", interactive: true)
    expect(word.literal_text).to eq('ab')
  end

  it 'ends the word at a continuation that ends the final buffer' do
    expect(field("a\\\n")).to eq('a')
  end

  it 'honours backslash escapes inside double quotes' do
    expect(field('"a\\"b"')).to eq('a"b')
    expect(field('"a\\zb"')).to eq('a\\zb')
  end

  it 'removes a backslash-newline inside double quotes' do
    expect(field("\"a\\\nb\"")).to eq('ab')
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

  it 'drops a final continuation in whole mode regardless of interactive input policy' do
    scanner = StringScanner.new("a\\\n")
    word = described_class.new(scanner, terminator: nil, interactive: true).scan
    expect(word.literal_text).to eq('a')
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

  describe 'segment quoting flags' do
    def shape(source)
      scan(source).first.segments.map { |segment| [segment.value, segment.quoted] }
    end

    it 'marks a bare param segment unquoted and a double-quoted one quoted' do
      expect(scan('$x').first.segments.first.quoted).to be(false)
      expect(scan('"$x"').first.segments.map { |s| [segment_kind(s), s.quoted] }).to eq([[:param, true]])
    end

    it 'marks a bare backtick substitution unquoted' do
      expect(scan('`date`').first.segments.first.quoted).to be(false)
    end

    it 'keeps double-quoted literal content as one quoted segment' do
      expect(shape('"ab"')).to eq([['ab', true]])
    end

    it 'keeps an escaped special the only quoted segment of its quotes' do
      expect(shape('"\\$"')).to eq([['$', true]])
    end

    it 'keeps the backslash before an ordinary character in double quotes' do
      expect(shape('"\\z"')).to eq([['\\', true], ['z', true]])
    end

    it 'keeps a lone quoted dollar a quoted literal' do
      expect(shape('"$"')).to eq([['$', true]])
    end

    it 'reads a double-quoted command substitution as exactly one segment' do
      expect(scan('"`c`"').first.segments.map { |s| segment_kind(s) }).to eq([:command])
      expect(scan('"$x"').first.segments.map { |s| segment_kind(s) }).to eq([:param])
    end

    it 'keeps empty single quotes as one empty quoted segment' do
      expect(shape("''")).to eq([['', true]])
    end

    it 'marks a bare escaped character quoted' do
      expect(shape('\\z')).to eq([['z', true]])
    end

    it 'keeps a trailing backslash as one unquoted literal' do
      expect(shape('a\\')).to eq([['a\\', false]])
    end
  end
end
